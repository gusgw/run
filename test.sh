#! /bin/bash


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

function log_setting {
    # Make sure a setting is provided
    # and report it
    local description=$1
    local setting=$2
    not_empty "date stamp" "${STAMP}"
    not_empty "$description" "$setting"
    >&2 echo "${STAMP}: ${description} is ${setting}"
}

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

function kids {

    # TODO make sure recursive output is
    # TODO not on multiple lines

    local pid="$1"

    not_empty "pid to check for children" "$pid"

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

./one.sh &
oneid=$!
sleep 5
echo "$$"
echo "$oneid"
echo $(kids "$oneid")
for k in {1..60}; do
    echo "test: $k"
    echo "$$"
    echo "$oneid"
    echo $(kids "$$")
    sleep 10
done
exit 0
