function get_inputs {

    nice -n "${NICE}" rclone sync \
                "${input}/" \
                "${work}/" \
                --config "${run_path}/rclone.conf" \
                --log-level WARNING \
                --log-file "${logs}/${STAMP}.${job}.rclone.input.log" \
                --transfers "${INBOUND_TRANSFERS}" \
                --include "${inglob}.gpg" ||\
        report $? "download input data"
    nice -n "${NICE}" rclone sync \
                "${input}/" \
                "${work}/" \
                --config "${run_path}/rclone.conf" \
                --log-level WARNING \
                --log-file "${logs}/${STAMP}.${job}.rclone.input.log" \
                --transfers "${INBOUND_TRANSFERS}" \
                --include "${inglob}" ||\
        report $? "download input data"

    return 0
}

function decrypt_inputs {

    for file in ${work}/${inglob}.gpg; do
        if [ -e "${file}" ]; then
            find "${work}" -name "${inglob}.gpg" |\
                parallel --results "${logs}/gpg/input/{/}/" \
                         --joblog "${logs}/${STAMP}.${job}.gpg.input.log" \
                         --jobs "$MAX_SUBPROCESSES" ${OPT_PARALLEL} \
                    nice -n "${NICE}" gpg --output {.} \
                                          --compress-algo 0 \
                                          --batch \
                                          --yes \
                                          --with-colons \
                                          --always-trust \
                                          --lock-multiple {} &
            local di_parallel_pid=$!
            while kill -0 "$di_parallel_pid" 2> /dev/null; do
                sleep ${WAIT}
                load_report "${job} decrypt"  "${logs}/${STAMP}.${job}.$$.load"
                free_memory_report "${job} gpg" \
                                   "${logs}/${STAMP}.${job}.$$.free"
            done
        fi
        break
    done

    return 0
}

function encrypt_outputs {

    find "${work}" -name "${outglob}" |\
        parallel --results "${logs}/gpg/output/{/}/" \
                 --joblog "${logs}/${STAMP}.${job}.gpg.output.log" \
                 --jobs "$MAX_SUBPROCESSES" ${OPT_PARALLEL} \
            nice -n "${NICE}" gpg --output {}.gpg \
                                  --compress-algo 0 \
                                  --batch \
                                  --yes \
                                  --with-colons \
                                  --always-trust \
                                  --lock-multiple \
                                  --sign --local-user "$sign" \
                                  --encrypt --recipient "$encrypt" {} &
    # local eo_parallel_pid=$!
    # while kill -0 "$eo_parallel_pid" 2> /dev/null; do
    #     sleep ${WAIT}
    #     load_report "${job} encrypt"  "${logs}/${STAMP}.${job}.$$.load"
    #     free_memory_report "${job} gpg" \
    #                        "${logs}/${STAMP}.${job}.$$.free"
    # done

    return 0
}

function send_outputs {

    # for file in ${work}/${outglob}.gpg; do
    if [ "${encrypt_flag}" == "yes" ]; then
        nice -n "${NICE}" rclone copy \
                "${work}/" \
                "${output}/" \
                --config "${run_path}/rclone.conf" \
                --log-level WARNING \
                --log-file "${logs}/${STAMP}.${job}.rclone.output.log" \
                --include "${outglob}.gpg" \
                --transfers "${OUTBOUND_TRANSFERS}" ||\
            report $? "save results"
    else
        nice -n "${NICE}" rclone copy \
                "${work}/" \
                "${output}/" \
                --config "${run_path}/rclone.conf" \
                --log-level WARNING \
                --log-file "${logs}/${STAMP}.${job}.rclone.output.log" \
                --include "${outglob}" \
                --transfers "${OUTBOUND_TRANSFERS}" ||\
            report $? "save results"
    fi
    return 0
}

function poll_outputs {

    local po_pid_monitor=$1
    local po_wait=$2
    not_empty "$po_pid_monitor" "PID to monitor in loop condition"
    not_empty "$po_wait" "time between checks for outputs"

    while kill -0 "$po_pid_monitor" 2> /dev/null; do

        sleep "${po_wait}"

        # Encrypt the results
        if [ "${encrypt_flag}" == "yes" ]; then
            >&2 echo "${STAMP}: calling encrypt_outputs"
            encrypt_outputs
        fi

        # Save the results to the output destination
        send_outputs

    done
}