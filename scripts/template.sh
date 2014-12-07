#!/bin/bash

# notify failure without root permissions, and exit
[ $(id -u) -ne 0 ] && echo "execution will fail without root permissions..." && exit 1

##
# request additional information
##

echo -n "enter an ssh port (default: 22): "
read ssh_port

echo -n "enter a hostname (default: $service): "
read system_hostname

echo -n "enter a domain name (optional): "
read domainname

echo -n "enter a timezone path (default: /usr/share/zoneinfo/US/Eastern): "
read timezone

echo -n "enable jis (y|n, default: y): "
read jis

echo "would you like to generate an ssh key (y|n, default: y)?"
read create_ssh

# set defaults
[ -z "$ssh_port" ] && ssh_port=22
[ -z "$timezone" ] && timezone="/usr/share/zoneinfo/US/Eastern"
[ -z "$jis" ] && jis="y"
[ -z "$system_hostname" ] && system_hostname=$service
[ -z "$create_ssh" ] && create_ssh="y"

# install netselect-apt and find the best mirrors
# then get the system updated before we go forward
aptitude install -ryq netselect-apt
mv /etc/apt/sources.list /etc/apt/sources.list.bak
netselect-apt -sn -o /etc/apt/sources.list
aptitude clean
if ! aptitude update
then
    mv /etc/apt/sources.list.bak /etc/apt/sources.list
    aptitude clean
    aptitude update
fi
aptitude upgrade -yq

# silently install template packages /w recommends
aptitude install -ryq screen tmux vim git mercurial bzr subversion command-not-found bash-completion unzip monit ntp resolvconf watchdog ssh sudo whois rsync curl e2fsprogs parted os-prober

# execute first-run warmups
update-command-not-found

# enable watchdog
update-rc.d watchdog defaults

# optimize lvm
sed -i 's/issue_discards = 0/issue_discards = 1/' /etc/lvm/lvm.conf

# fix permissions
sed -i 's/UMASK\s*022/UMASK        002/' /etc/login.defs
if [ $(grep -c "umask=002" /etc/pam.d/common-session) -eq 0 ]
then
    echo "session optional pam_umask.so umask=002" >> /etc/pam.d/common-session
fi

# install cronjobs
[ -f "data/etc/cron.daily/system-updates" ] && cp "data/etc/cron.daily/system-updates" "/etc/cron.daily/system-updates"  || $dl_cmd "/etc/cron.daily/system-updates" "${remote_source}data/etc/cron.daily/system-updates"
[ -f "data/etc/cron.weekly/disk-maintenance" ] && cp "data/etc/cron.weekly/disk-maintenance" "/etc/cron.weekly/disk-maintenance"  || $dl_cmd "/etc/cron.daily/system-updates" "${remote_source}data/etc/cron.weekly/disk-maintenance"

# install monit configs
[ -f "data/etc/monit/monitrc.d/system" ] && cp "data/etc/monit/monitrc.d/system" "/etc/monit/monitrc.d/system"  || $dl_cmd "/etc/monit/monitrc.d/system" "${remote_source}data/etc/monit/monitrc.d/system"
[ -f "data/etc/monit/monitrc.d/ssh" ] && cp "data/etc/monit/monitrc.d/ssh" "/etc/monit/monitrc.d/ssh"  || $dl_cmd "/etc/monit/monitrc.d/ssh" "${remote_source}data/etc/monit/monitrc.d/ssh"
[ -f "data/etc/monit/monitrc.d/web" ] && cp "data/etc/monit/monitrc.d/web" "/etc/monit/monitrc.d/web"  || $dl_cmd "/etc/monit/monitrc.d/web" "${remote_source}data/etc/monit/monitrc.d/web"

# activate with symlinks
ln -nsf "../monitrc.d/system" "/etc/monit/conf.d/system"
ln -nsf "../monitrc.d/ssh" "/etc/monit/conf.d/ssh"
ln -nsf "../monitrc.d/web" "/etc/monit/conf.d/web"

# test and restart monit
monit -t && service monit restart

# set system timezone
ln -nsf $timezone /etc/localtime

# update hostname & hosts file /w domain info
if [ -n "$system_hostname" ]
then
    echo "$system_hostname" > /etc/hostname
    hostname -F /etc/hostname
    [ -n "$domainname" ] && sed -i "s/127.0.1.1.*/127.0.1.1 ${system_hostname}.${domainname} ${system_hostname}/" /etc/hosts
fi

# fix grub kernel panics
if [ -f /etc/default/grub ]
then
    sed -i 's/GRUB_COMMANDLINE_LINUX_DEFALT=.*/GRUB_COMMANDLINE_LINUX_DEFALT="quiet panic=10"/' /etc/default/grub
    update-grub
fi

# secure ssh & restart service
sed -i "s/Port\s*[0-9].*/Port ${ssh_port}/" /etc/ssh/sshd_config
sed -i "s/^#\?PasswordAuthentication\s*[yn].*/PasswordAuthentication no/" /etc/ssh/sshd_config
sed -i "s/^#\?PermitRootLogin.*[yn].*/PermitRootLogin no/" /etc/ssh/sshd_config
service ssh restart

# install iptables
mkdir -p /etc/iptables
$dl_cmd "/etc/iptables/iptables.rules" "${remote_source}data/etc/iptables/iptables.rules"
$dl_cmd "/etc/network/if-up.d/iptables" "${remote_source}data/etc/network/if-up.d/iptables"
chmod +x "/etc/network/if-up.d/iptables"
[ "$ssh_port" != "22" ] && sed -i "s/ 22 / $ssh_port /" /etc/iptables/iptables.rules

# optionally enable jis locale & rebuild
if [ "$jis" = "y" ] && [ $(grep -c "ja_JP.UTF-8" /etc/locale.gen) -eq 1 ]
then
    sed -i "s/# ja_JP\.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/" /etc/locale.gen
    locale-gen
fi

# install custom fonts & rebuild cache
mkdir -p /usr/share/fonts/ttf/jis
$dl_cmd "/usr/share/fonts/ttf/jis/ForMateKonaVe.ttf" "${remote_source}data/home/.fonts/ForMateKonaVe.ttf"
$dl_cmd "/usr/share/fonts/ttf/jis/epkyouka.ttf" "${remote_source}data/home/.fonts/epkyouka.ttf"
fc-cache -fr

# attempt to run dot-files installer as root so it adds to /etc/skel
. <($source_cmd "$dot_files")

# fix potential permission problems with logs
chown -R root:adm /var/log/*

# ensure vim is set as default editor
update-alternatives --set editor /usr/bin/vim.basic

# conditionally create new user and add to core groups
useradd -m -s /bin/bash -p $(mkpasswd -m md5 "$password") $username
usermod -aG sudo,adm $username

# generate ssh key
if [ "$create_ssh" = "y" ]
then
    mkdir -p "/home/$username/.ssh"
    ssh-keygen -q -b 4096 -t rsa -N "$password" -f "/home/$username/.ssh/id_rsa"
    chmod 600 /home/$username/.ssh/*
fi

if [ -n "$github_username" ] && [ -n "$github_password" ]
then
    # attempt to upload new ssh key to github account
    curl -i -u "${github_username}:${github_password}" -H "Content-Type: application/json" -H "Accept: application/json" -X POST -d "{\"title\":\"$(hostname -s) ($(date '+%Y/%m/%d'))\",\"key\":\"$(cat /home/${username}/.ssh/id_rsa.pub)\"}" https://api.github.com/user/keys
fi

# download `update-keys
mkdir -p /home/$username/.bin
[ -f "data/home/.bin/update-keys" ] && cp "data/home/.bin/update-keys" "/home/${username}/.bin/update-keys"  || $dl_cmd "/home/${username}/.bin/update-keys" "${remote_source}data/home/.bin/update-keys"

# @todo add crontab to run `update-keys`
# need to test something like this
# line="* * * * * /path/to/command"
# (crontab -u userhere -l; echo "$line" ) | crontab -u userhere -

# reset ownership on user files
chown -R $username:$username /home/$username