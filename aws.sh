# Check for a spot interruption notice in the instance metadata
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/
# spot-instance-termination-notices.html
function spot_interruption_found {
    local ec2_metadata_save=$1
    log_setting "file to save metadata" "$ec2_metadata_save"
    ec2-metadata 2> /dev/null 1> "$ec2_metadata_save" ||\
            report $? "checking for ec2 metadata"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" \
                    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` &&\
            curl -H "X-aws-ec2-metadata-token: $TOKEN" \
                http://169.254.169.254/latest/meta-data/spot/instance-action |\
            grep -qs "404 - Not Found"
        return $?
    else
        # If the ec2-metadata command failed,
        # we should not report a spot interruption with
        # a non-zero code.
        return 0
    fi
}

# While a given process is running, check for a spot
# interruption periodically. If an interruption notice
# is found report and trigger cleanup and shutdown.
function poll_spot_interruption {
    local psi_pid=$1
    local psi_wait=$2
    not_empty "$psi_pid" "PID running while interruption checks needed"
    not_empty "$psi_wait" "time between checks for an interruption notice"
    while kill -0 "$psi_pid" 2> /dev/null; do
        sleep "$psi_wait"
        spot_interruption_found "${logs}/${STAMP}.${job}.$$.metadata" ||\
                                report "${SHUTDOWN_SIGNAL}" \
                                "checking for interruption" \
                                "spot interruption detected"
    done
}
