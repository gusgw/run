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

    ######################################################################
    # Signal GNU Parallel if necessary
    # One TERM signal stops new jobs from starting,
    # two term signals kills existing jobs.
    if [ -n "$parallel_pid" ]; then
        log_setting "PID of GNU Parallel for cleanup" "$parallel_pid"
        if kill -0 "$parallel_pid" 2> /dev/null; then
            >&2 echo "${STAMP}: signalling parallel"
            kill -TERM "$parallel_pid"
            kill -TERM "$parallel_pid"
        fi
    fi

    ######################################################################
    # Save the status of this process and kill remaining workers
    # before the rest of the cleanup work

    >&2 echo "${STAMP}: checking for child processes"

    local status="${logs}/status/$$.${STAMP}.cleanup.status"
    cp "/proc/$$/status" "$status"
    chmod u+w "$status"

    while read pid; do
        while kill -0 "${pid%% *}" 2> /dev/null; do
            >&2 echo "${STAMP}: ${pid} is still running - trying to stop it"
            kill "${pid%% *}" || report $? "killing $pid"
            sleep ${WAIT}
        done
    done < $ramdisk/workers

    ######################################################################
    # Encrypt the results
    if [ "${encrypt_flag}" == "yes" ]; then
        >&2 echo "${STAMP}: calling encrypt_outputs"
        encrypt_outputs
    fi

    ######################################################################
    # Save the results to the output destination
    >&2 echo "${STAMP}: saving outputs"
    send_outputs

    if ! [ "$clean" == "keep" ]; then
        >&2 echo "${STAMP}: removing downloaded input files"
        for f in ${work}/${inglob}.gpg; do
            rm -f ${f} || report $? "remove input file ${f}"
        done
        for f in ${work}/${inglob}; do
            rm -f ${f} || report $? "remove input file ${f}"
        done
    fi

    if [ "$clean" == "output" ] || [ "$clean" == "gpg" ] || [ "$clean" == "all" ]; then
        >&2 echo "${STAMP}: removing output files"
        for f in "${work}/${outglob}"; do
            rm -f ${f} || report $? "remove raw output ${f}"
        done
    else
        >&2 echo "${STAMP}: keeping output files"
    fi

    if [ "$clean" == "gpg" ] || [ "$clean" == "all" ]; then
        >&2 echo "${STAMP}: removing GPG files"
        for gpg in "${work}/${outglob}.gpg"; do
            rm -f ${gpg} || report $? "remove signed and encrypted ${gpg}"
        done
    else
        >&2 echo "${STAMP}: keeping GPG files"
    fi

    local log_archive="${work}/${STAMP}.${job}.$$.logs.tar.xz"
    savewd="$(pwd)"
    cd "${logspace}" && tar Jcvf "${log_archive}" "${job}/"
    cd "${savewd}"
    rclone copy "${log_archive}" \
                "${output}/" \
                --config "${run_path}/rclone.conf" \
                --log-level WARNING \
                --transfers "${OUTBOUND_TRANSFERS}" ||\
        report $? "sending logs to output folder"

    if [ "$clean" == "all" ]; then
        rm -rf ${work} || report $? "removing work folder"
    else
        >&2 echo "${STAMP}: keeping work folder"
    fi

    if [ "$clean" == "all" ]; then
        rm -rf ${logs} || report $? "removing log folder"
    else
        >&2 echo "${STAMP}: keeping log folder"
    fi

    rm $ramdisk/workers
    rm -rf $ramdisk

    >&2 echo "${STAMP}: . . . all done with code ${rc}"
    >&2 echo "---"
    if [ "$clean" == "all" ] && [ "$rc" -eq 0 ]; then
        sudo shutdown now
    else
        exit $rc
    fi
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
