# Check for a spot interruption notice in the instance metadata
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/
# spot-instance-termination-notices.html
function spot_interruption_found {
    TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" \
                -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` &&\
        curl -H "X-aws-ec2-metadata-token: $TOKEN" \
            http://169.254.169.254/latest/meta-data/spot/instance-action |\
        grep -qs "404 - Not Found"
    return $?
}
