export RULE="***"

export NICE=19

work="${workspace}/${job}"
log_setting "workspace subfolder for this job" "${work}"
mkdir -p "${work}" || report $? "create work folder for $job"

logs="${logspace}/${job}"
log_setting "log subfolder for this job" "${logs}"
mkdir -p "${logs}" || report $? "create log folder for $job"
mkdir -p "${logs}/status" || report $? "create status folder for $job"

ramdisk="/dev/shm/${job}/$$"
log_setting "ramdisk space for this job" "${ramdisk}"
mkdir -p "${ramdisk}" || report $? "setup ramdisk for $job"

insize=$(nice -n "${NICE}" rclone lsl "${input}/" \
                                      --include "${inglob}" |\
                           awk '{sum+=$1} END {print sum;}')
log_setting "size of inputs" "${insize}"
worksize=$(echo ${insize}*${workfactor}+1 | bc -l | sed 's/\([0-9]*\)\..*$/\1/')
log_setting "size needed for workspace" "${worksize}"