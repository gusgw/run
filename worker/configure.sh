#! /bin/bash

key=$1
ip=$2
deploy=$3
rclone=$4
asc=$5

SSHCMD="ssh -i ~/.ssh/${key}" 
SCPCMD="scp -i ~/.ssh/${key}"
WORKER="admin@${ip}"

while ! "${SSHCMD}" "${WORKER}" which git; do
    sleep 5
done

"${SSHCMD}" "${WORKER}" << ENDSSH
rm -rf ~/.ssh/${deploy}
rm -rf ~/.ssh/config
rm -rf ~/.gnupg
ENDSSH

"${SCPCMD}" ~/.ssh/${deploy} "${WORKER}:~/.ssh/"
"${SCPCMD}" ${asc}/*.asc "${WORKER}:~/"
"${SCPCMD}" ${rclone} "${WORKER}:~/"

"${SSHCMD}" "${WORKER}" << ENDSSH
    chmod og-rw ~/.ssh/${deploy}
    cat > ~/.ssh/config << EOF
        Host github
            HostName        github.com
            User            git
            Port            22
            IdentityFile    ~/.ssh/id_ed25519-tobermory-github_deploy
    EOF
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts

    mkdir -p ~/src/
    cd ~/src/
    rm -rf run
    git clone -b develop github:gusgw/run.git 1> ~/git.clone.out 2> ~/git.clone.err
    cd run
    git submodule update --init --recursive 1> ~/git.sub.out 2> ~/git.sub.err

    rm rclone.conf
    ln -s ~/${rclone} rclone.conf

    cd
    gpg --import *.asc

    sudo mkfs.ext4 /dev/nvme1n1
    sudo mkdir -p /mnt/data
    sudo mount /dev/nvme1n1 /mnt/data
    sudo chown admin /mnt/data
ENDSSH
