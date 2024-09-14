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

    local status="${logs}/status/$$.${STAMP}.cleanup.status"
    cp "/proc/$$/status" "$status"
    chmod u+w "$status"

    while read pid; do
        while kill -0 "${pid%% *}" 2> /dev/null; do
            >&2 echo "${STAMP}: ${pid} is still running - trying to stop it"
            kill $pid || report $? "killing $pid"
            sleep ${WAIT}
        done
    done < $ramdisk/workers

    # rm $ramdisk/workers
    # rm -rf $ramdisk

    >&2 echo "${STAMP}: . . . all done with code ${rc}"
    >&2 echo "---"
    exit $rc
}

export parallel_cleanup_function="parallel_cleanup_run"

function parallel_cleanup_run {
    local rc=$1
    >&2 echo "---"
    >&2 echo "${STAMP}" "${PARALLEL_PID}" \
                        "${PARALLEL_JOBSLOT}" \
                        "${PARALLEL_SEQ}: exiting run cleanly with code ${rc}. . ."
    whoami="$$.${PARALLEL_PID}.${PARALLEL_JOBSLOT}.${PARALLEL_SEQ}"
    local status="${logs}/status/${whoami}.${STAMP}.parallel_cleanup.status"
    cp "/proc/$$/status" "$status" || parallel_report $? "copy status files"
    chmod u+w "$status"
    >&2 echo "${STAMP}" "${PARALLEL_PID}" \
                        "${PARALLEL_JOBSLOT}" \
                        "${PARALLEL_SEQ}: . . . all done with code ${rc}"
    >&2 echo "---"
    return $rc
}
export -f parallel_cleanup_run