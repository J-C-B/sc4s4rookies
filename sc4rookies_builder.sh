#!/bin/bash

# 23/07/21 John Barnett
# Script created on / for CentOS 8
# Community script to create a Splunk Enterprise node from scratch, use at your own risk
# 

################################################################################################################
## It is designed to run once and assumes a clean system and takes little care as to any existing config    ####
################################################################################################################

# Set URL and Tokens here
HEC_URL="https://127.0.0.1:8088"
HEC_TOKEN="e82f986a-7582-41f8-83c3-86c98ba278b6"
#HEC_TOKEN="520b411a-3949-4c2c-948a-01eaf6a35f34"
splunkwebpw=sc4s4logs

################################################################################################################
################################################################################################################
########################## Further below, there be dragons - know what you are doing :) ########################
################################################################################################################
################################################################################################################
red=`tput setaf 1`
green=`tput setaf 2`
yellow=`tput setaf 3`
reset=`tput sgr0`

# Create users
adduser splunk

# Add users to group required
groupadd splunk
usermod -aG splunk splunk
echo -e "sc4s4logs\nsc4s4logs\n" | passwd splunk

echo "${yellow}allow Splunk to restart the sc4s systemd service${reset}"

#allow Splunk to restart the sc4s systemd service

echo "
## Created with JB Splunk Install script by magic
%splunk ALL= NOPASSWD: /bin/systemctl start sc4s
%splunk ALL= NOPASSWD: /bin/systemctl stop sc4s
%splunk ALL= NOPASSWD: /bin/systemctl restart sc4s
%splunk ALL= NOPASSWD: /bin/systemctl status sc4s
%splunk ALL= NOPASSWD: /bin/podman logs SC4S
%splunk ALL= NOPASSWD: /bin/podman ps
" >  /etc/sudoers.d/splunk

echo "AllowUsers  root  splunk" >> /etc/ssh/sshd_config

sudo systemctl restart sshd

echo "${yellow}#set local logs to go to sc4s${reset}"

#set local logs to go to sc4s

echo "
## Created with JB Splunk Install script by magic
*.* @127.0.0.1:514           # Use @ for UDP protocol
" >>  /etc/rsyslog.conf


################################################################################################################
## Firewalls and Networking  ####
################################################################################################################


## Needed for AWS Centos8 Image
sudo dnf install firewalld
sudo systemctl enable firewalld
sudo systemctl start firewalld

echo "${yellow}Firewalls and Networking${reset}"

#Show original state
firewall-cmd --list-all

# add 443 redirect - https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-port_forwarding

#ubuntu
#iptables -t nat -I PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 8443

#centos 8
firewall-cmd --add-forward-port=port=443:proto=tcp:toport=8443 # firewall redirect so low port without root
firewall-cmd --zone=public --add-port=443/tcp --permanent # alt Web UI Port
#firewall-cmd --zone=public --add-port=9090/tcp --permanent # cockpit
firewall-cmd --add-masquerade


#Splunk ports
firewall-cmd --zone=public --add-port=8443/tcp --permanent # Web UI Port
firewall-cmd --zone=public --add-port=8080/tcp --permanent # HEC port
firewall-cmd --zone=public --add-port=8088/tcp --permanent # HEC port
firewall-cmd --zone=public --add-port=8089/tcp --permanent # Managment Port
firewall-cmd --zone=public --add-port=9997/tcp --permanent # Data flow

#Syslog listeners (if opening to external sources)
#firewall-cmd --zone=public --add-port=514/tcp --permanent
#firewall-cmd --zone=public --add-port=514/udp --permanent
#firewall-cmd --zone=public --add-port=6514/tcp --permanent
#firewall-cmd --zone=public --add-port=1514/tcp --permanent
#firewall-cmd --zone=public --add-port=1514/udp --permanent


firewall-cmd --runtime-to-permanent
firewall-cmd --reload
#Check applied
firewall-cmd --list-all

################################################################################################################
## THP and file limits ####
################################################################################################################


echo "${yellow}Deal with THP${reset}"

# Deal with THP
# https://docs.splunk.com/Documentation/Splunk/7.2.5/ReleaseNotes/SplunkandTHP

# Check THP status

cat /sys/kernel/mm/transparent_hugepage/enabled
cat /sys/kernel/mm/transparent_hugepage/defrag

# Disable THP at boot
echo "
## Created with JB Splunk Install script by magic
 [Unit]
 Description=Disable Transparent Huge Pages (THP)
 
 [Service]
 Type=simple
 ExecStart=/bin/sh -c \"echo \'never\' > /sys/kernel/mm/transparent_hugepage/enabled && echo \'never\' > /sys/kernel/mm/transparent_hugepage/defrag\"
 
 [Install]
 WantedBy=multi-user.target
" >  /etc/systemd/system/disable-thp.service

sudo systemctl daemon-reload

# Start the disable-thp daemon
systemctl start disable-thp

# Disable THP at startup
systemctl enable disable-thp

# THP now diabled
cat /sys/kernel/mm/transparent_hugepage/enabled
cat /sys/kernel/mm/transparent_hugepage/defrag

echo "${yellow}Set file limits${reset}"
# Set file limits

mkdir /etc/systemd/user.conf.d/

echo "
## Created with JB Splunk Install script by magic
## https://docs.splunk.com/Documentation/Splunk/8.0.3/Installation/Systemrequirements#Considerations_regarding_system-wide_resource_limits_on_.2Anix_systems
[Manager]
DefaultLimitFSIZE=-1
DefaultLimitNOFILE=64000
DefaultLimitNPROC=16000
#LimitFSIZE=infinity   # A setting of infinity sets the file size to unlimited.
#LimitDATA=8000000000  #8GB - The maximum RAM you want Splunk Enterprise to allocate in bytes
#TasksMax=16000        #The maximum number of tasks that a service can create. This setting aligns with the user process limit LimitNPROC and the value can be set to match. For example, 16000
" > /etc/systemd/user.conf.d/splunk.conf


echo "${yellow}Update and install packages${reset}"
#Update package lists
dnf update -y

#systemctl enable --now cockpit.socket

find /usr/share/nano -name '*.nanorc' -printf "include %p\n" > ~/.nanorc

# get the repo
dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y
dnf config-manager --set-enabled PowerTools

dnf install multitail htop iptraf-ng nano wget tcpdump python3 -y


################################################################################################################
## Install and setup Splunk  ####
################################################################################################################

echo "${yellow}Time for the Splunky Sauce, you lucky devils${reset}"
# add Splunk
cd /opt
mkdir splunk

wget -O splunk-8.2.1-ddff1c41e5cf-Linux-x86_64.tgz 'https://www.splunk.com/bin/splunk/DownloadActivityServlet?architecture=x86_64&platform=linux&version=8.2.1&product=splunk&filename=splunk-8.2.1-ddff1c41e5cf-Linux-x86_64.tgz&wget=true'

tar -xf splunk-8.2.1-ddff1c41e5cf-Linux-x86_64.tgz

chown -R splunk:splunk splunk

# Skip Splunk Tour and Change Password Dialog
touch /opt/splunk/etc/.ui_login


########################## Adding the TAs

echo "${yellow}Adding the SC4S TAs${reset}"

mkdir /opt/deps
cd /opt/deps

# Rookies apps

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/TA-sc4s-1.0.0.spl

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/sc4s-4rookies-1.0.4.spl

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/TA-sc4s-datagen-1.0.4.spl

# Splunk Apps and TAs

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/config-explorer_149.spl

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/force-directed-app-for-splunk_310.tgz

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/infosec-app-for-splunk_170.tgz

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/lookup-file-editor_350.tgz

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/punchcard-custom-visualization_150.tgz

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/splunk-add-on-for-cisco-asa_410.spl

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/splunk-add-on-for-unix-and-linux_830.tgz

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/splunk-common-information-model-cim_4200.tgz

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/splunk-sankey-diagram-custom-visualization_160.tgz


for f in *.spl; do
  tar -xf "$f" -C /opt/splunk/etc/apps/ &
done

for f in *.tgz; do
  tar -xf "$f" -C /opt/splunk/etc/apps/ &
done


echo "${yellow}Setting the config explorer to hide settings and allow editing${reset}"

sudo cd /opt/splunk/etc/apps/config_explorer/

sudo mkdir /opt/splunk/etc/apps/config_explorer/local


echo "
[global]
# set for sc4s4rookies
write_access = true

hide_settings = true

" > /opt/splunk/etc/apps/config_explorer/local/config_explorer.conf


# Enable SSL Login for Splunk

# Set webui port to 8443 (uses iptables port 443 redirect)

echo "
## Created with JB Splunk Install script by magic
[settings]
httpport = 8443
enableSplunkWebSSL = true
login_content = Welcome to Splunk SC4S4Rookies, It's going to be a blast - Splunk 4TW!
" > /opt/splunk/etc/system/local/web.conf

# enable the http input function on the node

mkdir /opt/splunk/etc/apps/splunk_httpinput/local/

echo "
## Created with JB Splunk Install script by magic
#enable the http input function on the node (disabled by default)
[http]
disabled = 0
enableSSL = 1

[http://sc4s4rookiesl]
disabled = 0
host = sc4s4roookieshec
token = $HEC_TOKEN

" > /opt/splunk/etc/apps/splunk_httpinput/local/inputs.conf

mkdir /opt/splunk/etc/system/local/

echo "
## Created with JB Splunk Install script by magic
#enable all idx for user experience (disabled by default)

[role_admin]
edit_log_alert_event = disabled
grantableRoles = admin
search_process_config_refresh = disabled
srchIndexesAllowed = *;_*;main
srchIndexesDefault = *;main
srchMaxTime = 8640000
" > /opt/splunk/etc/system/local/authorize.conf


echo "${yellow}Starting Splunk - fire it up!! and enabling Splunk to start at boot time with user=splunk${reset}"

chown -R splunk:splunk /opt/splunk

/opt/splunk/bin/splunk enable boot-start -user splunk --accept-license --seed-passwd $splunkwebpw --answer-yes --auto-ports --no-prompt

chown -R splunk:splunk /opt/splunk

# Add extra users if wanted example

#/opt/splunk/bin/splunk add user user1 -password V6jwLHLqiZdpwXsPQUHc -role admin -auth admin:$splunkwebpw
#/opt/splunk/bin/splunk add user user2 -password V6jwLHLqiZdpwXsPQUHc -role admin -auth admin:Bz9!SV8VdRiYiman
#/opt/splunk/bin/splunk add user user3 -password V6jwLHLqiZdpwXsPQUHc -role admin -auth admin:Bz9!SV8VdRiYiman
#/opt/splunk/bin/splunk add user user4 -password V6jwLHLqiZdpwXsPQUHc -role admin -auth admin:Bz9!SV8VdRiYiman

/opt/splunk/bin/splunk start


echo "${yellow}Check the login page is there${reset}"

curl -k https://127.0.0.1:8443/en-gb/


################################################################################################################
## Add sc4s  ####
################################################################################################################


# Script created on / for CentOS 8 - TLS Remix
### Based on quick start here - https://splunk-connect-for-syslog.readthedocs.io/en/master/gettingstarted/quickstart_guide/
### podman run -ti drwetter/testssl.sh --severity MEDIUM --ip 127.0.0.1 fooo:6514


################################################################################
########### Dont edit below here, unless you know what you are doing ###########
################################################################################
echo "${yellow}Time for some SC4S baby!${reset}"

echo "${yellow}Check date and TZ below!${reset}"
date 

echo "${yellow}Updating Firewall Rules${reset}"


dnf install -y conntrack podman

echo "
## Edited with JB Splunk Install script by magic
net.core.rmem_default = 17039360
net.core.rmem_max = 17039360
" >> /etc/sysctl.conf

sysctl -p

echo "
## Created with JB Splunk Install script by magic
[Unit]
Description=SC4S Container
Wants=NetworkManager.service network-online.target
After=NetworkManager.service network-online.target
[Install]
WantedBy=multi-user.target
[Service]
Environment=\"SC4S_IMAGE=docker.io/splunk/scs:latest\"
# Required mount point for syslog-ng persist data (including disk buffer)
Environment=\"SC4S_PERSIST_MOUNT=splunk-sc4s-var:/var/lib/syslog-ng\"
# Optional mount point for local overrides and configurations; see notes in docs
Environment=\"SC4S_LOCAL_MOUNT=/opt/splunk/sc4s/local:/etc/syslog-ng/conf.d/local:z\"
# Optional mount point for local disk archive (EWMM output) files
Environment=\"SC4S_ARCHIVE_MOUNT=/opt/splunk/sc4s/archive:/var/lib/syslog-ng/archive:z\"
# Uncomment the following line if custom TLS certs are provided
Environment=\"SC4S_TLS_MOUNT=/opt/splunk/sc4s/tls:/etc/syslog-ng/tls:z\"
TimeoutStartSec=0
ExecStartPre=/usr/bin/podman pull \$SC4S_IMAGE
ExecStartPre=/usr/bin/bash -c \"/usr/bin/systemctl set-environment SC4SHOST=$(hostname -s)\"
ExecStart=/usr/bin/podman run \\
        -e \"SC4S_CONTAINER_HOST=\${SC4SHOST}\" \\
        -v \$SC4S_PERSIST_MOUNT \\
        -v \$SC4S_LOCAL_MOUNT \\
        -v \$SC4S_ARCHIVE_MOUNT \\
        -v \$SC4S_TLS_MOUNT \\
        --env-file=/opt/splunk/sc4s/env_file \\
        --network host \\
        --name SC4S \\
        --rm \$SC4S_IMAGE
Restart=on-abnormal
" > /lib/systemd/system/sc4s.service

sudo podman volume create splunk-sc4s-var
sudo mkdir /opt/splunk/sc4s/ 
mkdir /opt/splunk/sc4s/local 
mkdir /opt/splunk/sc4s/archive 
mkdir /opt/splunk/sc4s/tls

# SET CORRECT URL AND HEC TOKEN HERE
echo "
## Created with JB Splunk Install script by magic

# Output config
# URL to send syslog too

SPLUNK_HEC_URL=$HEC_URL

# HEC token        

SPLUNK_HEC_TOKEN=$HEC_TOKEN

#Uncomment the following line if using untrusted SSL certificates
SC4S_DEST_SPLUNK_HEC_TLS_VERIFY=no

# TLS Config, for McAfee etc if needed
SC4S_SOURCE_TLS_ENABLE=yes
SC4S_LISTEN_DEFAULT_TLS_PORT=6514
" > /opt/splunk/sc4s/env_file

echo "${yellow}Generating Cert for TLS${reset}"

openssl req -newkey rsa:2048 -new -nodes -x509 -days 3650 -subj "/C=NZ/ST=NI/L=Home/O=SC4S Name/OU=Org/CN=sc4sbuilder" -keyout /opt/splunk/sc4s/tls/server.key -out /opt/splunk/sc4s/tls/server.pem

echo "${yellow}Your /opt/splunk/sc4s/env_file looks like this${reset}"

cat /opt/splunk/sc4s/env_file

echo "${yellow}Starting SC4S - This might take a while first time as the container is downloaded${reset}"

sudo systemctl daemon-reload 
sudo systemctl enable --now sc4s

# Send a test event
echo “Hello MYSC4S4rookies” > /dev/udp/127.0.0.1/514
sleep 10
sudo podman logs SC4S
sudo podman ps
# Sleep to allow TLS to come up
sleep 20
netstat -tulpn | grep LISTEN
#### Use command below and then type to test
#openssl s_client -connect localhost:6514
#### Use command below for full tls test if required (adjust as needed)
#podman run -ti drwetter/testssl.sh --severity MEDIUM --ip 192.168.2.163 sc4sbuilder:6514
sleep 1
sudo systemctl stop sc4s

# Set ownership so configexplorer can edit the files as Splunk user

chown -R splunk:splunk /opt/splunk/sc4s


sudo systemctl restart rsyslog
sudo podman ps