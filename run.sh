#! /bin/bash

# Set the folder where this script is located
# so that other files can be found.
export run_path=$(dirname $(realpath  $0))

# Load useful routines
# https://github.com/gusgw/bump
. ${run_path}/bump/bump.sh
. ${run_path}/bump/parallel.sh

export WAIT=10.0
export output_wait=120.0

export MAX_SUBPROCESSES=2
INBOUND_TRANSFERS=4
export OUTBOUND_TRANSFERS=4

export OPT_NICELOAD=""
export OPT_PARALLEL=""

ec2_flag="no"

clean="$1"      # What should be cleaned up in the workspace?
export job="$2"        # Give this run a name or number.

# Specify inputs to fetch to workspace with rclone
input="dummy:/mnt/data/chips/input"
# input="aws-sydney-std:cavewall-tobermory-mnt-data-chips-input-test-0/"
iext="input"
inglob="*.${iext}"

# Specify outputs to get from workspace with rclone when done
export output="dummy:/mnt/data/chips/output"
# export output="aws-sydney-std:cavewall-tobermory-mnt-data-chips-output-test-0/"
oext="output"
export outglob="*.${oext}"

# Where is the working directory?
workspace="/mnt/data/chips/work"

# Estimate the size of files generated as a multiple of input size
workfactor=1.2

# Where should logs be stored?
logspace="/mnt/data/chips/log"

# Set a target system load visible to subprocesses
export target_load=6.0

# Specify keys for decryption of inputs,
# and for signing and encryption of outputs
export encrypt_flag="yes"
export sign="0x0EBB90D1DC0B1150FF99A356E46ED00B12038406"
export encrypt="0x67FC8A8BDC06FA0CAC4B0F5BB0F8791F5D69F478"

# Run type should be test if we're using a dummy
# job to test the script.
# Export the variables because they are used in the processes
# spawned by GNU parallel.
export run_type="test"
export n_test_waits=6
export stress_cpus=2
export output_size="1G"

# Set information for log outputs
set_stamp

# Check commands are available
check_dependency rclone
check_dependency gpg
check_dependency gawk
check_dependency bc
check_dependency parallel
check_dependency niceload
check_dependency stress

# Report settings
log_setting "cleanup when done" "${clean}"
log_setting "job to process" "${job}"
log_setting "source for input data" "${input}"
log_setting "destination for outputs" "${output}"
log_setting "workspace" "${workspace}"
log_setting "log destination" "${logspace}"
log_setting "target system load" "${target_load}"
log_setting "signing key" "$sign"
log_setting "encryption key" "$encrypt"

# Automatic settings
. ${run_path}/settings.sh

# Load routines for fetching inputs and sending outputs
. ${run_path}/io.sh

# Load AWS specific routines
. ${run_path}/aws.sh

# Load cleanup and prepare to trap signals
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

    parallel_log_setting "workspace" "${work}"
    parallel_log_setting "log destination" "${logs}"
    parallel_log_setting "ramdisk space" "${ramdisk}"

    parallel_log_setting "job" "${job}"
    parallel_log_setting "file to work on" "${input}"

    parallel_log_setting "target system load" "${target_load}"

    parallel_check_exists "${input}"

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
        echo "working" &
        mainid=$!
    #---END---------
    fi

    if [[ "$run_type" == "test" ]]; then
    #---TEST-CODE---
        for k in $(seq 1 $n_test_waits); do
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
        wait $mainid || parallel_report $? "waiting for run to finish"
    #---END---------
    fi

    if [[ "$run_type" == "test" ]]; then
    #---TEST-CODE---
        dd if=/dev/random \
           of="${work}/${outname}.tmp" \
           bs="${output_size}" \
           count=1
        mv "${work}/${outname}.tmp" "${work}/${outname}"
    #---END---------
    fi

    parallel_cleanup 0
    return 0
}
export -f run

# Set a handler for signals that stop work
trap handle_signal 1 2 3 6 15

######################################################################
# Get the input data
get_inputs

######################################################################
# Decrypt inputs if necessary
decrypt_inputs

######################################################################
# Run the job
find "${work}" -name "${inglob}" |\
    parallel --results "${logs}/run/{/}/" \
             --joblog "${logs}/${STAMP}.${job}.run.log" \
             --jobs "${MAX_SUBPROCESSES}" ${OPT_PARALLEL}\
        run "${work}" "${logs}" "${ramdisk}" "${job}" {} &
parallel_pid=$!

# Periodically save information about resource usage
poll_reports "$parallel_pid" "$$" "${WAIT}" &
report_pid=$!
echo "${report_pid} reporting resource use" >> "${ramdisk}/workers"

# Periodically check for outputs, encrypt if necessary,
# and save to destination
poll_outputs "$parallel_pid" "${output_wait}" &
output_pid=$!
echo "${output_pid} saving outputs asap" >> "${ramdisk}/workers"

# Either run an empty loop waiting for work to complete
# or if appropriate poll for spot interruption notices
if [ "$ec2_flag" == "yes" ]; then
    poll_spot_interruption "${parallel_pid}" "${WAIT}"
else
    while kill -0 "$parallel_pid" 2> /dev/null; do
        sleep ${WAIT}
    done
fi

######################################################################
cleanup 0
