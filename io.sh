function get_inputs {

    nice -n "${NICE}" rclone sync \
                "${input}/" \
                "${work}/" \
                --config "${run_path}/rclone.conf" \
                --progress \
                --log-level INFO \
                --log-file "${logs}/${STAMP}.${job}.rclone.input.log" \
                --transfers "${INBOUND_TRANSFERS}" \
                --include "${inglob}.gpg" ||\
        report $? "download input data"
    print_rule
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
    print_rule

    return 0
}

function decrypt_inputs {

    for file in ${work}/${inglob}.gpg; do
        if [ -e "${file}" ]; then
            find "${work}" -name "${inglob}.gpg" |\
                parallel --results "${logs}/gpg/input/{/}/" \
                         --joblog "${logs}/${STAMP}.${job}.gpg.input.log" \
                         --jobs "$MAX_SUBPROCESSES" \
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
            echo
            print_rule
        fi
        break
    done

    return 0
}

function encrypt_outputs {

    find "${work}" -name "${outglob}" |\
        parallel --results "${logs}/gpg/output/{/}/" \
                 --joblog "${logs}/${STAMP}.${job}.gpg.output.log" \
                 --jobs "$MAX_SUBPROCESSES" \
            nice -n "${NICE}" gpg --output {}.gpg \
                                  --compress-algo 0 \
                                  --batch \
                                  --yes \
                                  --with-colons \
                                  --always-trust \
                                  --lock-multiple \
                                  --sign --local-user "$sign" \
                                  --encrypt --recipient "$encrypt" {} &
    local eo_parallel_pid=$!
    while kill -0 "$eo_parallel_pid" 2> /dev/null; do
        sleep ${WAIT}
        load_report "${job} encrypt"  "${logs}/${STAMP}.${job}.$$.load"
        free_memory_report "${job} gpg" \
                           "${logs}/${STAMP}.${job}.$$.free"
    done
    echo
    print_rule

    return 0
}

function send_outputs {

    for file in ${work}/${outglob}.gpg; do
        if [ -e "${file}" ]; then
            nice -n "${NICE}" rclone copy \
                    "${work}/" \
                    "${output}/" \
                    --config "${run_path}/rclone.conf" \
                    --progress \
                    --log-level INFO \
                    --log-file "${logs}/${STAMP}.${job}.rclone.output.log" \
                    --include "${outglob}.gpg" \
                    --transfers "${OUTBOUND_TRANSFERS}" ||\
                report $? "save results"
        else
            nice -n "${NICE}" rclone copy \
                    "${work}/" \
                    "${output}/" \
                    --config "${run_path}/rclone.conf" \
                    --progress \
                    --log-level INFO \
                    --log-file "${logs}/${STAMP}.${job}.rclone.output.log" \
                    --include "${outglob}" \
                    --transfers "${OUTBOUND_TRANSFERS}" ||\
                report $? "save results"
        fi
        break
    done

    return 0
}