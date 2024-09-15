#! /bin/bash

key=$1
deploy=$2
ip=$3

ssh -i "~/.ssh/${key}" "admin@${ip}" << ENDSSH
rm -rf ~/.ssh/${deploy}
rm -rf ~/.ssh/config
ENDSSH
scp -i ~/.ssh/${key} ~/.ssh/${deploy} admin@${ip}:~/.ssh/

ssh -i "~/.ssh/${key}" "admin@${ip}" << ENDSSH
chmod og-rw ~/.ssh/${deploy}
cat > ~/.ssh/config << EOF
Host github
    HostName        github.com
    User            git
    Port            22
    IdentityFile    ~/.ssh/id_ed25519-tobermory-github_deploy
EOF
ssh-keyscan -H [hostname] >> ~/.ssh/known_hosts
mkdir -p ~/src/
cd ~/src/
rm -rf run
git clone -b develop github:gusgw/run.git 1> ~/git.clone.out 2> ~/git.clone.err
cd run
git submodule update --init --recursive 1> ~/git.sub.out 2> ~/git.sub.err
ENDSSH
