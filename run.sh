#! /bin/bash

# Transfer seasonal data into Sydney AWS Buckets

MISSING_INPUT=60
MISSING_FILE=61
MISSING_FOLDER=62
MISSING_DISK=63
MISSING_MOUNT=64

BAD_CONFIGURATION=70
UNSAFE=71

SYSTEM_UNIT_FAILURE=80
SECURITY_FAILURE=81
NETWORK_ERROR=83

TRAPPED_SIGNAL=113

WAIT=5.0

MAX_SUBPROCESSES=16
INBOUND_TRANSFERS=8
OUTBOUND_TRANSFERS=8

export NICE=19

function set_stamp {
    # Store a stamp used to label files
    # and messages created in this script.
    local hostname=$(hostnamectl status | head -n 1 | sed 's/.*: \(.*\)/\1/')
    export STAMP="$(date '+%Y%m%d'-${hostname})-$$"
    return 0
}

function not_empty {
    # Ensure that an expression is not empty
    # then cleanup and quit if it is
    local description=$1
    local check=$2
    if [ -z "$check" ]; then
        >&2 echo "${STAMP}: cannot run without ${description}"
        cleanup "${MISSING_INPUT}"
    fi
    return 0
}
function _p_not_empty {
    # Ensure that an expression is not empty
    # then cleanup and quit if it is
    local description=$1
    local check=$2
    if [ -z "$check" ]; then
        >&2 echo "${STAMP} ${PARALLEL_PID}: cannot run without ${description}"
        _p_cleanup "${MISSING_INPUT}"
    fi
    return 0
}
export -f _p_not_empty

function log_setting {
    # Make sure a setting is provided
    # and report it
    local description=$1
    local setting=$2
    not_empty "date stamp" "${STAMP}"
    not_empty "$description" "$setting"
    >&2 echo "${STAMP}: ${description} is ${setting}"
}
function _p_log_setting {
    # Make sure a setting is provided
    # and report it
    local description=$1
    local setting=$2
    _p_not_empty "date stamp" "${STAMP}"
    _p_not_empty "$description" "$setting"
    >&2 echo "${STAMP} ${PARALLEL_PID}: ${description} is ${setting}"
}
export -f _p_log_setting

function report {
    # Inform the user of a non-zero return
    # code, cleanup, and if an exit
    # message is provided as a third argument
    # also exit
    local rc=$1
    local description=$2
    local exit_message=$3
    >&2 echo "${STAMP}: ${description} exited with code $rc"
    if [ -z "$exit_message" ]; then
        >&2 echo "${STAMP}: continuing . . ."
    else
        >&2 echo "${STAMP}: $exit_message"
        cleanup $rc
    fi
    return $rc
}
function _p_report {
    # Inform the user of a non-zero return
    # code, cleanup, and if an exit
    # message is provided as a third argument
    # also exit
    local rc=$1
    local description=$2
    local exit_message=$3
    >&2 echo "${STAMP} ${PARALLEL_PID}: ${description} exited with code $rc"
    if [ -z "$exit_message" ]; then
        >&2 echo "${STAMP} ${PARALLEL_PID}: continuing . . ."
    else
        >&2 echo "${STAMP} ${PARALLEL_PID}: $exit_message"
        _p_cleanup $rc
    fi
    return $rc
}
export -f _p_report

function check_exists {
    # Make sure a file or folder or link exists
    # then cleanup and quit if not
    local file_name=$1
    log_setting "file or directory name that must exist" "$file_name"
    if ! [ -e "$file_name" ]; then
        >&2 echo "${STAMP}: cannot find $file_name"
        cleanup "$MISSING_FILE"
    fi
    return 0
}
function _p_check_exists {
    # Make sure a file or folder or link exists
    # then cleanup and quit if not
    local file_name=$1
    _p_log_setting "file or directory name that must exist" "$file_name"
    if ! [ -e "$file_name" ]; then
        >&2 echo "${STAMP} ${PARALLEL_PID}: cannot find $file_name"
        _p_cleanup "$MISSING_FILE"
    fi
    return 0
}
export -f _p_check_exists

function size_distribution {
    local folder=$1
    local glob=$2

    log_setting "folder for file size distribution" "$folder"
    log_setting "glob for file size distribution" "$glob"

    check_exists "$folder"

    awk1='{size[int(log($5)/log(2))]++}'
    awk2='{for (i in size) printf("%10d %3d\n", 2^i, size[i])}'

    find "${folder}" -type f -wholename "${glob}" -print0 |\
        xargs -0 ls -l |\
        awk "${awk1}END${awk2}" |\
        sort -n

    return 0
}

function kids {

    # TODO make sure recursive output is
    # TODO not on multiple lines

    local pid="$1"

    _p_not_empty "pid to check for children" "$pid"

    for t in /proc/${pid}/task/*; do
        local children="${t}/children"
        if [ -e "$children" ]; then
            for kid in $(cat ${children}); do
                echo $kid
                kids "$kid"
            done
        fi
    done

    return 0
}
export -f kids

function cleanup {

    ######################################
    # If using the report function here, #
    # make sure it has NO THIRD ARGUMENT #
    # or there will be an infinite loop! #
    # This function may be used to       #
    # handle trapped signals             #
    ######################################

    local rc=$1
    >&2 echo "***"
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
        while kill -0 "$pid" 2> /dev/null; do
            >&2 echo "${STAMP}: ${pid} is still running - trying to stop it"
            kill $pid || report $? "killing $pid"
            sleep ${WAIT}
        done
    done < $ramdisk/workers

    rm $ramdisk/workers
    rm -rf $ramdisk

    >&2 echo "${STAMP}: . . . all done with code ${rc}"

    exit $rc
}
function _p_cleanup {

    # Exported version of the function cleanup
    # for use with GNU parallel.

    #########################################
    # If using the _p_report function here, #
    # make sure it has NO THIRD ARGUMENT    #
    # or there will be an infinite loop!    #
    # This function may be used to          #
    # handle trapped signals                #
    #########################################

    local rc=$1
    >&2 echo "***"
    >&2 echo "${STAMP} ${PARALLEL_PID}: exiting subprocess cleanly with code ${rc} . . ."
    >&2 echo "${STAMP} ${PARALLEL_PID}: . . . all done with code ${rc}"
    exit $rc
}
export -f _p_cleanup

function handle_signal {
    # cleanup and use error code if we trap a signal
    >&2 echo "${STAMP}: trapped signal during maintenance"
    cleanup "${TRAPPED_SIGNAL}"
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

    echo "$PARALLEL_PID" >> "${ramdisk}/workers"

    _p_log_setting "workspace" "${workspace}"
    _p_log_setting "job for parallel worker" "${job}"
    _p_log_setting "file to work on" "${input}"

    _p_check_exists "${workspace}"
    _p_check_exists "${input}"

    destination="${workspace}/${job}"
    _p_log_setting "destination for results" "$destination"
    mkdir -p "${destination}" ||\
        _p_report "$?" "make folder if necessary"
    _p_check_exists "${destination}"

    # TODO Spawn the process then periodically save its resource
    # TODO usage then report its exit code.
    nice -n "$NICE" stress --verbose \
                           --cpu 4 &
    stressid=$!
    echo "${stressid}" >> "${ramdisk}/workers"
    niceload -v --load 4.1 -p ${stressid} &
    for kid in $(kids ${stressid}); do
        echo "${kid}" >> "${ramdisk}/workers"
        niceload -v --load 4.1 -p ${kid} &
    done
    # wait $stressid || _p_report $? "working"
    sleep 120
    kill $stressid || _p_report $? "ending ${job}"

    dd if=/dev/random of="${destination}/chips.output" bs=1G count=1

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

sign="0x42B9BB51CE72038A4B97AD306F76D37987954AEC"
encrypt="0x1B1F9924BC54B2EFD61F7F12E017B2531D708EC4"

log_setting "signing key" "$sign"
log_setting "encryption key" "$encrypt"

######################################################################
# Make workspace.
# This folder is accessed by the worker function 'run'.

destination="${workspace}/${job}"
mkdir -p "${destination}" || report $? "create workspace for $job"
logs="${logspace}/${job}"
mkdir -p "${logs}" || report $? "create log folder for $job"
ramdisk="/dev/shm/${job}/$$/"
mkdir -p "${ramdisk}" || report $? "setup ramdisk for $job"

insize=$(nice -n "${NICE}" rclone lsl "${input}/" \
                                      --include "${inglob}" |\
                           awk '{sum+=$1} END {print sum;}')
worksize=$(echo ${insize}*${workfactor}+1 | bc -l | sed 's/\([0-9]*\)\..*$/\1/')

# Get the input data
# TODO: Convert to niceload
nice -n "${NICE}" rclone sync \
            "${input}/" \
            "${destination}/" \
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
            --progress \
            --log-level INFO \
            --log-file "${logs}/${STAMP}.${job}.rclone.output.log" \
            --include "${outglob}.gpg" \
            --transfers "${OUTBOUND_TRANSFERS}" ||\
    report $? "save results"

cleanup 0
