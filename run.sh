#! /bin/bash

# Set the folder where this script is located
# so that other files can be found.
run_path=$(dirname $(realpath  $0))

# Load useful routines
# https://github.com/gusgw/bump
. ${run_path}/bump/bump.sh
. ${run_path}/bump/parallel.sh

export WAIT=5.0

MAX_SUBPROCESSES=2
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
encrypt_outputs="no"
sign="0x42B9BB51CE72038A4B97AD306F76D37987954AEC"
encrypt="0x1B1F9924BC54B2EFD61F7F12E017B2531D708EC4"

# Run type should be test if we're using a dummy
# job to test the script
export run_type="test"
export stress_cpus=2
export output_size="1M"

# Check commands are available
check_dependency rclone
check_dependency gpg
check_dependency bc
check_dependency parallel
check_dependency niceload

set_stamp
log_setting "cleanup when done" "${clean}"
log_setting "job to process" "${job}"
log_setting "source for input data" "${input}"
log_setting "destination for outputs" "${output}"
log_setting "workspace" "${workspace}"
log_setting "log destination" "${logspace}"
log_setting "target system load" "${target_load}"
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

    if [[ "$run_type" == "test" ]]; then
    #---TEST-CODE---
        inputname=$(basename ${input})
        outname=${inputname/\.input/\.${job}\.output}
    #---END---------
    fi

    parallel_log_setting "working directory" "$work"
    mkdir -p "${work}" ||\
        parallel_report "$?" "make folder if necessary"
    parallel_check_exists "${work}"

    if [[ "$run_type" == "test" ]]; then
    #---TEST-CODE---
        nice -n "$NICE" stress --verbose --cpu "${stress_cpus}" &
        mainid=$!
    #---END---------
    else
    #---REAL CODE---
        echo "working"
        mainid=$!
    #---END---------
    fi

    if [[ "$run_type" == "test" ]]; then
    #---TEST-CODE---
        for k in {1..3}; do
            sleep ${WAIT};
            apply_niceload "${mainid}" \
                           "${ramdisk}/workers" \
                           "${target_load}"
        done
    #---END---------
    else
    #---REAL-CODE---
        while kill -0 "${mainid}" 2> /dev/null; do
            sleep ${WAIT};
            apply_niceload "${mainid}" \
                           "${ramdisk}/workers" \
                           "${target_load}"
        done
    #---END---------
    fi

    if [[ "$run_type" == "test" ]]; then
    #---TEST-CODE---
        kill $mainid || parallel_report $? "ending test ${job}"
    #---END---------
    else
    #---REAL-CODE---
        wait $mainid || parallel_report $? "working"
    #---END---------
    fi

    if [[ "$run_type" == "test" ]]; then
    #---TEST-CODE---
        dd if=/dev/random \
           of="${work}/${outname}" \
           bs="${output_size}" \
           count=1
    #---END---------
    fi

    parallel_cleanup 0
    return 0
}
export -f run

# Set a handler for signals that stop work
trap handle_signal 1 2 3 6 15

# Load routines for fetching inputs and sending outputs
. ${run_path}/io.sh

######################################################################
# Get the input data

get_inputs

######################################################################
# Decrypt inputs if necessary

decrypt_inputs

######################################################################
# Run the job

find "${work}" -name "${inglob}" |\
    parallel --eta --tag --tagstring {} \
             --results "${logs}/run/{/}/" \
             --joblog "${logs}/${STAMP}.${job}.run.log" \
             --jobs "${MAX_SUBPROCESSES}" \
        run "${work}" "${logs}" "${ramdisk}" "${job}" {} &

parallel_pid=$!
while kill -0 "$parallel_pid" 2> /dev/null; do
    sleep ${WAIT}
    load_report "${job} run" "${logs}/${STAMP}.${job}.$$.load"
    if [ -f "$ramdisk/workers" ]; then
        while read pid; do
            if kill -0 "${pid%% *}" 2> /dev/null; then
                memory_report "${job} run" "${pid%% *}" \
                              "${logs}/${STAMP}.${job}.${pid%% *}.memory"
            fi
        done < $ramdisk/workers
    fi
    free_memory_report "${job} run" \
                       "${logs}/${STAMP}.${job}.$$.free"
done
echo
print_rule

######################################################################
# Encrypt the results

if [ "${encrypt_outputs}" == "yes" ]; then
    encrypt_outputs
fi

######################################################################
# Save the results to the output destination

send_outputs

######################################################################
cleanup 0
