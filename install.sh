#!/bin/bash

# install.sh
# Copyright (C) 2017  Joe Testa <jtesta@positronsecurity.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms version 3 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

openssh_sources='openssh-7.5p1.tar.gz'
openssh_source_dir='openssh-7.5p1'
mitm_patch='openssh-7.5p1-mitm.patch'


# Resets the environment (in case this script was run once before).
function reset_env {

    # Remove files previously downloaded.
    rm -rf *.asc $openssh_sources $openssh_source_dir $openssh_source_dir-mitm

    # Make sure no sshd_mitm is running and the user is logged out.
    killall -u ssh-mitm 2> /dev/null

    # Check if the ssh-mitm user exists.
    id ssh-mitm > /dev/null 2> /dev/null
    if [[ $? == 0 ]]; then

	# The user exists.  If this script was run with the "--force" argument,
        # then we will delete the user.
        if [[ $1 == '--force' ]]; then
            userdel -f -r ssh-mitm 2> /dev/null

        # There could be saved sessions from an old version of SSH MITM that
        # we shouldn't destroy automatically.
        else
            echo "It appears that the ssh-mitm user already exists.  Make backups of any saved sessions in /home/ssh-mitm/, then re-run this script with the \"--force\" argument (this will cause the user account to be deleted and re-created)."
            exit -1
        fi
    fi

    return 1
}


# Installs prerequisites.
function install_prereqs {
    echo -e "Installing prerequisites...\n"

    declare -a packages
    packages=(autoconf build-essential zlib1g-dev)

    # Check if we are in Kali Linux.  Kali ships with OpenSSL v1.1.0, which
    # OpenSSH doesn't support.  So we need to explicitly install the v1.0.2
    # dev package.  Also, a bare-bones Kali installation may not have the
    # killall tool, so install that in the psmisc package.
    grep Kali /etc/lsb-release > /dev/null
    if [[ $? == 0 ]]; then
        packages+=(libssl1.0-dev psmisc)
    else
        packages+=(libssl-dev)
    fi

    apt install -y ${packages[@]}
    if [[ $? != 0 ]]; then
        echo -e "Failed to install prerequisites.  Failed: apt install -y ${packages[@]}"
        exit -1
    fi

    return 1
}


# Downloads OpenSSH and verifies its sources.
function get_openssh {
    local openssh_sig='openssh-7.5p1.tar.gz.asc'
    local release_key_fingerprint_expected='59C2 118E D206 D927 E667  EBE3 D3E5 F56B 6D92 0D30'
    local openssh_checksum_expected='9846e3c5fab9f0547400b4d2c017992f914222b3fd1f8eee6c7dc6bc5e59f9f0'

    echo -e "\nGetting OpenSSH release key...\n"
    wget https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/RELEASE_KEY.asc

    echo -e "\nGetting OpenSSH sources...\n"
    wget https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/$openssh_sources

    echo -e "\nGetting OpenSSH signature...\n"
    wget https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/$openssh_sig

    echo -e "\nImporting OpenSSH release key...\n"
    gpg --import RELEASE_KEY.asc

    local release_key_fingerprint_actual=`gpg --fingerprint 6D920D30`
    if [[ $release_key_fingerprint_actual != *"$release_key_fingerprint_expected"* ]]; then
        echo -e "\nError: OpenSSH release key fingerprint does not match expected value!\n\tExpected: $release_key_fingerprint_expected\n\tActual: $release_key_fingerprint_actual\n\nTerminating."
        exit -1
    fi
    echo -e "\n\nOpenSSH release key matches expected value.\n"

    local gpg_verify=`gpg --verify $openssh_sig $openssh_sources 2>&1`
    if [[ $gpg_verify != *"Good signature from \"Damien Miller <djm@mindrot.org>\""* ]]; then
        echo -e "\n\nError: OpenSSH signature invalid!\n$gpg_verify\n\nTerminating."
        rm -f $openssh_sources
        exit -1
    fi

    # Check GPG's return value.  0 denotes a valid signature, and 1 is returned
    # on invalid signatures.
    if [[ $? != 0 ]]; then
        echo -e "\n\nError: OpenSSH signature invalid!  Verification returned code: $?\n\nTerminating."
        rm -f $openssh_sources
        exit -1
    fi

    echo -e "Signature on OpenSSH sources verified.\n"

    local openssh_checksum_actual=`sha256sum $openssh_sources`
    if [[ $openssh_checksum_actual != "$openssh_checksum_expected"* ]]; then
        echo -e "Error: OpenSSH checksum is invalid!  Terminating."
        exit -1
    fi

    return 1
}


# Applies the MITM patch to OpenSSH and compiles it.
function compile_openssh {
    tar xzf $openssh_sources --no-same-owner
    if [ ! -d $openssh_source_dir ]; then
       echo "Failed to decompress OpenSSH sources!"
       exit -1
    fi
    mv $openssh_source_dir "$openssh_source_dir"-mitm
    openssh_source_dir="$openssh_source_dir"-mitm

    pushd $openssh_source_dir > /dev/null
    echo -e "Patching OpenSSH sources...\n"
    patch -p1 < ../$mitm_patch

    if [[ $? != 0 ]]; then
        echo "Failed to patch sources!: patch returned $?"
        exit -1
    fi

    echo -e "\nDone.  Running autoconf...\n"
    autoconf

    echo -e "\nDone.  Compiling modified OpenSSH sources...\n"

    ./configure --with-sandbox=no --with-privsep-user=ssh-mitm --with-privsep-path=/home/ssh-mitm/empty --with-pid-dir=/home/ssh-mitm --with-lastlog=/home/ssh-mitm
    make -j `nproc --all`
    popd > /dev/null

    # Ensure that sshd and ssh were built.
    if [[ (! -f $openssh_source_dir/sshd) || (! -f $openssh_source_dir/ssh) ]]; then
        echo -e "\nFailed to build ssh and/or sshd.  Terminating."
        exit -1
    fi
}


# Creates the ssh-mitm user account, and sets up its environment.
function setup_environment {
    echo -e "\nCreating ssh-mitm user, and setting up its environment...\n"

    # Create the ssh-mitm user and set its home directory to mode 0700.  Create
    # "bin" and "etc" subdirectories to hold the executables and config file,
    # respectively.
    useradd -m -s /bin/bash ssh-mitm
    chmod 0700 ~ssh-mitm
    mkdir -m 0755 ~ssh-mitm/{bin,etc}
    mkdir -m 0700 ~ssh-mitm/tmp
    chown ssh-mitm:ssh-mitm ~ssh-mitm/tmp

    # Copy the config file to the "etc" directory.
    cp $openssh_source_dir/sshd_config ~ssh-mitm/etc/

    # Copy the executables to the "bin" directory.
    cp $openssh_source_dir/sshd ~ssh-mitm/bin/sshd_mitm
    cp $openssh_source_dir/ssh ~ssh-mitm/bin/ssh

    # Strip the debugging symbols out of the executables.
    strip ~ssh-mitm/bin/sshd_mitm ~ssh-mitm/bin/ssh

    # Create a 4096-bit RSA host key and ED25519 host key.
    ssh-keygen -t rsa -b 4096 -f /home/ssh-mitm/etc/ssh_host_rsa_key -N ''
    ssh-keygen -t ed25519 -f /home/ssh-mitm/etc/ssh_host_ed25519_key -N ''

    # Create the "empty" directory to make the privsep function happy.
    mkdir -m 0700 ~ssh-mitm/empty

    # Set ownership on the "empty" directory and SSH host keys.
    chown ssh-mitm:ssh-mitm /home/ssh-mitm/empty /home/ssh-mitm/etc/ssh_host_*key*

    # Create the "run.sh" script, then set its permissions.
    cat > ~ssh-mitm/run.sh <<EOF
#!/bin/bash
/home/ssh-mitm/bin/sshd_mitm -f /home/ssh-mitm/etc/sshd_config
if [[ $? == 0 ]]; then
    echo "sshd_mitm is now running."
    exit 0
else
    echo -e "\n\nERROR: sshd_mitm failed to start!\n"
    exit -1
fi
EOF
    chmod 0755 ~ssh-mitm/run.sh

    # Install the AppArmor profiles.
    if [[ ! -d /etc/apparmor.d ]]; then
        mkdir -m 0755 /etc/apparmor.d
    fi
    cp apparmor/home.ssh-mitm.bin.sshd_mitm /etc/apparmor.d/
    cp apparmor/home.ssh-mitm.bin.ssh /etc/apparmor.d/

    # Enable the profiles.
    service apparmor reload 2> /dev/null

    # Print a warning if AppArmor isn't installed, but continue on anyway.
    # The user may not want it on their system, so we shouldn't force it.
    if [[ $? != 0 ]]; then
        echo -e "\n\n\t!!! WARNING !!!: AppArmor is not installed.  It is highly recommended (though not required) that sshd_mitm is run in a restricted environment.\n\n\tInstall AppArmor with: \"apt install apparmor\".\n"

        # Kali needs extra instructions in order to get AppArmor installed.
        grep Kali /etc/lsb-release > /dev/null
        if [[ $? == 0 ]]; then
            echo -e "\n\tKali Linux requires extra steps to get AppArmor installed and functional.  Ensure profiles are loaded upon boot-up with:\n\n\t\t# update-rc.d apparmor enable\n\n\tAppArmor must be enabled on boot-up.  Edit the /etc/default/grub file, and change the following line:\n\n\t\tGRUB_CMDLINE_LINUX_DEFAULT=\"quiet\"\n\n\tto:\n\n\t\tGRUB_CMDLINE_LINUX_DEFAULT=\"quiet apparmor=1 security=apparmor\"\n\n\tLastly, reboot the system.\n"
        fi
    fi
}


if [[ `id -u` != 0 ]]; then
    echo "Error: this script must be run as root."
    exit -1
fi

install_prereqs
reset_env $1
get_openssh
compile_openssh
setup_environment

echo -e "\n\nDone!  The next step is to use JoesAwesomeSSHMITMVictimFinder.py to find target IPs, then execute start.sh and ARP spoof.\n\n"
exit 0
