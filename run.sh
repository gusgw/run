#! /bin/bash

# Set the folder where this script is located
# so that other files can be found.
run_path=$(dirname $(realpath  $0))

# Load useful routines
# https://github.com/gusgw/bump
. ${run_path}/bump/bump.sh
. ${run_path}/bump/parallel.sh

WAIT=10.0

MAX_SUBPROCESSES=16
INBOUND_TRANSFERS=8
OUTBOUND_TRANSFERS=8

clean="$1"      # What should be cleaned up in the workspace?
job="$2"        # Give this run a name or number.

# Specify inputs to fetch to workspace with rclone
input="dummy:/mnt/data/chips/input"
iext="input"
inglob="*.${iext}"

# Specify outputs to get from workspace with rclone when done
output="dummy:/mnt/data/chips/output"
oext="output"
outglob="*.${oext}"

# Where is the working directory?
workspace="/mnt/data/chips/work"

# Estimate the size of files generated as a multiple of input size
workfactor=1.2

# Where should logs be stored?
logspace="/mnt/data/chips/log"

# Set a target system load visible to subprocesses
export target_load=4.1

# Specify keys for decryption of inputs,
# and for signing and encryption of outputs
decrypt=""
sign="0x42B9BB51CE72038A4B97AD306F76D37987954AEC"
encrypt="0x1B1F9924BC54B2EFD61F7F12E017B2531D708EC4"

set_stamp
log_setting "cleanup when done" "${clean}"
log_setting "job to process" "${job}"
log_setting "source for input data" "${input}"
log_setting "destination for outputs" "${output}"
log_setting "workspace" "${workspace}"
log_setting "log destination" "${logspace}"
log_setting "target system load" "${target_load}"
# log_setting "decryption key" "$decrypt"
log_setting "signing key" "$sign"
log_setting "encryption key" "$encrypt"

. ${run_path}/settings.sh
. ${run_path}/cleanup.sh

# run "${workspace}" "${log}" "${ramdisk}" "${job}" {}
function run {
    # The workspace is the top level folder
    local work="$1"
    # Location for logs
    local logs="$2"
    # Ramdisk
    local ramdisk="$3"
    # Job to do
    local job="$4"
    # File to work on
    local input="$5"

    parallel_log_setting "job" "${job}"
    parallel_log_setting "file to work on" "${input}"
    parallel_log_setting "workspace" "${work}"
    parallel_log_setting "log destination" "${logs}"
    parallel_log_setting "ramdisk space" "${ramdisk}"
    parallel_log_setting "target system load" "${target_load}"

    parallel_check_exists "${work}"
    parallel_check_exists "${input}"
    parallel_check_exists "${ramdisk}"

    #---TEST CODE---
    inputname=$(basename ${input})
    outname=${inputname/\.input/\.${job}\.output}
    #---END  TEST---

    parallel_log_setting "working directory" "$work"
    mkdir -p "${work}" ||\
        parallel_report "$?" "make folder if necessary"
    parallel_check_exists "${work}"

    #---TEST CODE---
    # TODO Spawn the process then periodically save its resource
    # TODO usage then report its exit code.
    nice -n "$NICE" stress --verbose --cpu 2 &
     #---END  TEST---

    mainid=$!
    # TODO check $stressid is still running
    echo "${mainid} main job" >> "${ramdisk}/workers"
    niceload -v --load "${target_load}" -p "${mainid}" &
    sleep 10
    for kid in $(kids ${mainid}); do
        echo "${kid} child job" >> "${ramdisk}/workers"
        niceload -v --load "${target_load}" -p "${kid}" &
        parallel_log_setting "a process under load control" "${kid}"
    done
    # wait $mainid || parallel_report $? "working"

    #---TEST CODE---
    sleep 240
    #---END  TEST---

    kill $mainid || parallel_report $? "ending ${job}"

    #---TEST CODE---
    dd if=/dev/random of="${work}/${outname}" bs=1G count=1
    #---END  TEST---

    parallel_cleanup 0
    return 0
}
export -f run

# Set a handler for signals that stop work
trap handle_signal 1 2 3 6 15

######################################################################
# Get the input data

nice -n "${NICE}" rclone sync \
            "${input}/" \
            "${work}/" \
            --config "${run_path}/rclone.conf" \
            --progress \
            --log-level INFO \
            --log-file "${logs}/${STAMP}.${job}.rclone.input.log" \
            --transfers "${INBOUND_TRANSFERS}" \
            --include "${inglob}" ||\
    report $? "download input data"

######################################################################
# Run the job

find "${work}" -name "${inglob}" |\
    parallel --results "${logs}/run/{/}/" \
             --joblog "${logs}/${STAMP}.${job}.run.log" \
             --jobs "${MAX_SUBPROCESSES}" \
        run "${workspace}" "${logs}" "${ramdisk}" "${job}" {}

######################################################################
# Encrypt the results

find "${work}" -name "${outglob}" |\
    parallel --results "${logs}/gpg/{/}/" \
             --joblog "${logs}/${STAMP}.${job}.gpg.log" \
             --jobs "$MAX_SUBPROCESSES" \
        nice -n "${NICE}" gpg --output {}.gpg \
                              --compress-algo 0 \
                              --batch \
                              --yes \
                              --with-colons \
                              --always-trust \
                              --lock-multiple \
                              --sign --local-user "$sign" \
                              --encrypt --recipient "$encrypt" {}

######################################################################
# Save the results to the 

nice -n "${NICE}" rclone sync \
            "${work}/" \
            "${output}/" \
            --config "${run_path}/rclone.conf" \
            --progress \
            --log-level INFO \
            --log-file "${logs}/${STAMP}.${job}.rclone.output.log" \
            --include "${outglob}.gpg" \
            --transfers "${OUTBOUND_TRANSFERS}" ||\
    report $? "save results"

######################################################################
cleanup 0
