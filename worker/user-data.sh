#! /bin/bash

rm -rf /etc/update-motd.d/10-uname
rm -rf /etc/motd

apt -y update 1> /root/apt.update.out 2> /root/apt.update.err
apt -y upgrade 1> /root/apt.upgrade.out 2> /root/apt.upgrade.err

for pkg in git gawk bc gnupg2 htop stress rclone parallel; do
    apt -y install ${pkg} 1> /root/apt.${pkg}.out 2> /root/apt.${pkg}.err
done
