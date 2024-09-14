#! /bin/bash

# Set the folder where this script is located
# so that other files can be found.
run_path=$(dirname $(realpath  $0))

# Load useful routines from bump
# https://github.com/gusgw/bump
. ${run_path}/bump/bump.sh
. ${run_path}/bump/parallel.sh

WAIT=5.0

MAX_SUBPROCESSES=16
INBOUND_TRANSFERS=8
OUTBOUND_TRANSFERS=8

export RULE="***"

export NICE=19

cleanup_functions+=('cleanup_run')

function cleanup_run {

    ######################################
    # If using the report function here, #
    # make sure it has NO THIRD ARGUMENT #
    # or there will be an infinite loop! #
    # This function may be used to       #
    # handle trapped signals             #
    ######################################

    local rc=$1
    >&2 echo "---"
    >&2 echo "${STAMP}: exiting cleanly with code ${rc}. . ."

    if [ "$clean" == "input" ] || [ "$clean" == "all" ]; then
        >&2 echo "${STAMP}: removing downloaded input files"
        for f in ${destination}/${inglob}; do
            rm -f ${f} || report $? "remove input file ${f}"
        done
    else
        >&2 echo "${STAMP}: keeping downloaded input files"
    fi

    if [ "$clean" == "output" ] || [ "$clean" == "all" ]; then
        >&2 echo "${STAMP}: removing output files"
        for f in "${destination}/${outglob}"; do
            rm -f ${f} || report $? "remove raw output ${f}"
        done
    else
        >&2 echo "${STAMP}: keeping output files"
    fi

    if [ "$clean" == "gpg" ] || [ "$clean" == "all" ]; then
        >&2 echo "${STAMP}: removing GPG files"
        for gpg in "${destination}/${outglob}.gpg"; do
            rm -f ${gpg} || report $? "remove signed and encrypted ${gpg}"
        done
    else
        >&2 echo "${STAMP}: keeping GPG files"
    fi

    >&2 echo "${STAMP}: checking for child processes"

    local status="${STAMP}.cleanup.status"
    cp "/proc/$$/status" "$status"
    chmod u+w "$status"

    while read pid; do
        while kill -0 "${pid%% *}" 2> /dev/null; do
            >&2 echo "${STAMP}: ${pid} is still running - trying to stop it"
            kill $pid || report $? "killing $pid"
            sleep ${WAIT}
        done
    done < $ramdisk/workers

    rm $ramdisk/workers
    rm -rf $ramdisk

    >&2 echo "${STAMP}: . . . all done with code ${rc}"
    >&2 echo "---"
    exit $rc
}

parallel_cleanup_functions+=('parallel_cleanup_run')

function parallel_cleanup_run {

    local rc=$1
    >&2 echo "---"
    >&2 echo "${STAMP} ${PARALLEL_PID}: exiting cleanly with code ${rc}. . ."
    >&2 echo "${STAMP} ${PARALLEL_PID}: . . . all done with code ${rc}"
}

# run "${workspace}" "${log}" "${ramdisk}" "${job}" {}
# TODO: Convert to niceload
function run {
    # The workspace is the top level folder
    local workspace="$1"
    # Location for logs
    local logs="$2"
    # Ramdisk
    local ramdisk="$3"
    # Job to do
    local job="$4"
    # File to work on
    local input="$5"

    echo "$PARALLEL_PID parallel pid" >> "${ramdisk}/workers"

    parallel_log_setting "workspace" "${workspace}"
    parallel_log_setting "log destination" "${logs}"
    parallel_log_setting "ramdisk space" "${ramdisk}"
    parallel_log_setting "job for parallel worker" "${job}"
    parallel_log_setting "file to work on" "${input}"

    parallel_check_exists "${workspace}"
    parallel_check_exists "${input}"

    inputname=$(basename ${input})
    outname=${inputname/\.input/\.${job}\.output}

    destination="${workspace}/${job}"
    parallel_log_setting "working directory" "$destination"
    mkdir -p "${destination}" ||\
        parallel_report "$?" "make folder if necessary"
    parallel_check_exists "${destination}"

    # TODO Spawn the process then periodically save its resource
    # TODO usage then report its exit code.
    nice -n "$NICE" stress --verbose \
                           --cpu 4 &
    stressid=$!
    # TODO check $stressid is still running
    echo "${stressid} main job" >> "${ramdisk}/workers"
    niceload -v --load 4.1 -p ${stressid} &
    sleep 10
    for kid in $(kids ${stressid}); do
        echo "${kid} child job" >> "${ramdisk}/workers"
        niceload -v --load 4.1 -p ${kid} &
        parallel_log_setting "a process under load control" "${kid}"
    done
    # wait $stressid || parallel_report $? "working"
    sleep 120
    kill $stressid || parallel_report $? "ending ${job}"

    dd if=/dev/random of="${destination}/${outname}" bs=1G count=1

    parallel_cleanup 0
    return 0
}
export -f run

set_stamp

# Set a handler for signals that stop work
trap handle_signal 1 2 3 6 15

clean="$1"
job="$2"

iext="input"
oext="output"

input="dummy:/mnt/data/chips/input"
inglob="*.${iext}"
outglob="*.${oext}"
workspace="/mnt/data/chips/work"
workfactor=1.2
logspace="/mnt/data/chips/log"
output="dummy:/mnt/data/chips/output"

log_setting "source for input data" "${input}"
log_setting "workspace for data" "${workspace}"
log_setting "job to process" "${job}"
log_setting "destination for outputs" "${output}"

decrypt=""
sign="0x42B9BB51CE72038A4B97AD306F76D37987954AEC"
encrypt="0x1B1F9924BC54B2EFD61F7F12E017B2531D708EC4"

# log_setting "decryption key" "$decrypt"
log_setting "signing key" "$sign"
log_setting "encryption key" "$encrypt"

######################################################################
# Make workspace.
# This folder is accessed by the worker function 'run'.

destination="${workspace}/${job}"
log_setting "workspace subfolder for this job" "${destination}"
mkdir -p "${destination}" || report $? "create workspace for $job"
logs="${logspace}/${job}"
log_setting "log subfolder for this job" "${logs}"
mkdir -p "${logs}" || report $? "create log folder for $job"
ramdisk="/dev/shm/${job}/$$/"
log_setting "ramdisk space for this job" "${ramdisk}"
mkdir -p "${ramdisk}" || report $? "setup ramdisk for $job"

insize=$(nice -n "${NICE}" rclone lsl "${input}/" \
                                      --include "${inglob}" |\
                           awk '{sum+=$1} END {print sum;}')
log_setting "size of inputs" "${insize}"
worksize=$(echo ${insize}*${workfactor}+1 | bc -l | sed 's/\([0-9]*\)\..*$/\1/')
log_setting "size needed for workspace" "${worksize}"

# Get the input data
# TODO: Convert to niceload
nice -n "${NICE}" rclone sync \
            "${input}/" \
            "${destination}/" \
            --config "${run_path}/rclone.conf" \
            --progress \
            --log-level INFO \
            --log-file "${logs}/${STAMP}.${job}.rclone.input.log" \
            --transfers "${INBOUND_TRANSFERS}" \
            --include "${inglob}" ||\
    report $? "download input data"

######################################################################
# Process the data

find "${destination}" -name "${inglob}" |\
    parallel --bar \
             --results "${logs}/run/{/}/" \
             --joblog "${logs}/${STAMP}.${job}.run.log" \
             --jobs "${MAX_SUBPROCESSES}" \
        run "${workspace}" "${logs}" "${ramdisk}" "${job}" {}

######################################################################
# Encrypt the results
# TODO: Include niceload and or semaphore here

find "${destination}" -name "${outglob}" |\
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
# Save the results to the destination
# TODO: Convert to niceload

nice -n "${NICE}" rclone sync \
            "${destination}/" \
            "${output}" \
            --config "${run_path}/rclone.conf" \
            --progress \
            --log-level INFO \
            --log-file "${logs}/${STAMP}.${job}.rclone.output.log" \
            --include "${outglob}.gpg" \
            --transfers "${OUTBOUND_TRANSFERS}" ||\
    report $? "save results"

cleanup 0
