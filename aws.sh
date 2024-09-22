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
