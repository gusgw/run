#! /bin/bash

export WAIT=10.0
export SKIP=1
export MAX_WAIT=12

export worker="tobermory-2"
export rclone="${worker}-rclone.conf"
export deploy="id_ed25519-tobermory-github_deploy"
export branch="develop"

mkdir -p /root/user-data-output
chmod a+rwx /root/user-data-output

rm -rf /etc/update-motd.d/10-uname
rm -rf /etc/motd

apt -y update \
    1> /root/user-data-output/apt.update.out \
    2> /root/user-data-output/apt.update.err
apt -y upgrade \
    1> /root/user-data-output/apt.upgrade.out \
    2> /root/user-data-output/apt.upgrade.err

for pkg in git gawk bc gnupg2 htop stress rclone parallel; do
    apt -y install ${pkg} \
        1> /root/user-data-output/apt.${pkg}.out \
        2> /root/user-data-output/apt.${pkg}.err
done

counter=0
while ! id admin; do
    sleep 5
    counter=$(( counter+1 ))
    if [ "$counter" -ge "$MAX_WAIT" ]; then
        break
    fi 
done

mkfs.ext4 /dev/nvme1n1
mkdir -p /mnt/data
mount /dev/nvme1n1 /mnt/data
mkdir -p /mnt/data/log
chown --recursive admin /mnt/data

mkdir -p /home/admin/bin
chown admin /home/admin/bin

sudo -u admin -i \
    1> /root/user-data-output/configure.out \
    2> /root/user-data-output/configure.err << EOS
cd
pwd
whoami
export PATH="/home/admin/bin:${PATH}"
echo ${PATH}

# Cleanup just in case
rm -rf ~/${rclone}
rm -rf ~/.ssh/${deploy}
rm -rf ~/.ssh/config
rm -rf ~/.gnupg

# Set up rclone access to S3
cat > ~/${rclone} << EOF
[aws-sydney-std]
type = s3
provider = AWS
env_auth = true
region = ap-southeast-2
location_constraint = ap-southeast-2
acl = private
server_side_encryption = AES256
storage_class = STANDARD
EOF

# Read only deploy keys only
cat > ~/.ssh/${deploy} << EOF
{{ deploy }}
EOF

# Setup ssh access
chmod og-rw ~/.ssh/${deploy}
cat > ~/.ssh/config << EOF
Host github
    HostName        github.com
    User            git
    Port            22
    IdentityFile    ~/.ssh/${deploy}
EOF
ssh-keyscan -H github.com >> ~/.ssh/known_hosts

# Private key for decryption and signing
cat > ~/input.private.asc << EOF
{{ input }}
EOF

# Public key for encryption
cat > ~/output.public.asc << EOF
{{ output }}
EOF

# Load runner script
mkdir -p ~/src/
cd ~/src/
rm -rf run
git clone -b ${branch} github:gusgw/run.git \
                1> ~/git.clone.out \
                2> ~/git.clone.err
cd run
git submodule update --init --recursive \
                1> ~/git.sub.out \
                2> ~/git.sub.err

# Set up transfers
rm rclone.conf
ln -s ~/${rclone##*/} rclone.conf

# Import keys
cd
gpg --import *.asc

# Install metadata script
mkdir -p bin
cd bin
wget  http://s3.amazonaws.com/ec2metadata/ec2-metadata
chmod u+x ./ec2-metadata

# Link the runner for easy execution
ln -s ../src/run/run.sh run

# Run the job
~/bin/run all 0 \
    1> /mnt/data/log/run.out \
    2> /mnt/data/log/run.err
EOS
