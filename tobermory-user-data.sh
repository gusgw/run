#! /bin/bash

apt -y update 1> ~/apt.out 2> ~/apt.update.err
apt -y upgrade 1> ~/apt.upgrade.out 2> ~/apt.upgrade.err

for pkg in git bc gnupg2 rclone parallel; do
    apt -y install "${pkg}" 1> "apt.${pkg}.out" 2> "apt.${pkg}.err"
done
