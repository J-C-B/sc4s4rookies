#!/bin/bash

# 06/09/21 John Barnett
# Script created on / for CentOS 8 (AWS)
# Community script to create a Splunk Connect For Syslog 4ROOKIES node with existing Splunk from scratch, use at your own risk
# 

################################################################################################################
## It is designed to run once and assumes a clean system and takes little care as to any existing config    ####
################################################################################################################

# Set URL and Tokens here
HEC_URL="https://127.0.0.1:8088"
HEC_TOKEN="e82f986a-7582-41f8-83c3-86c98ba278b6"

################################################################################################################
################################################################################################################
########################## Further below, there be dragons - know what you are doing :) ########################
################################################################################################################
################################################################################################################
red=`tput setaf 1`
green=`tput setaf 2`
yellow=`tput setaf 3`
reset=`tput sgr0`



#set local logs to go to sc4s

echo "
## Created with JB Splunk Install script by magic
*.* @127.0.0.1:514           # Use @ for UDP protocol
" >>  /etc/rsyslog.conf


echo "${yellow}Update and install packages${reset}"
#Update package lists

sudo dnf install nano python3 -y

find /usr/share/nano -name '*.nanorc' -printf "include %p\n" > ~/.nanorc

################################################################################################################
## Install and setup Splunk  ####
################################################################################################################


########################## Adding the TAs

echo "${yellow}Adding the SC4S TAs${reset}"

mkdir /opt/deps
cd /opt/deps

# Rookies apps

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/TA-sc4s-1.0.0.spl

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/sc4s-4rookies-1.0.8.spl

wget https://johnb-bucket-pub.s3.ap-southeast-2.amazonaws.com/sc4s4rookies/TA-sc4s-datagen-1.0.7.spl

########################## Splunk Apps and TAs

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

sudo chown -R splunk:splunk splunk

echo "${yellow}Setting the config explorer to hide settings and allow editing${reset}"

sudo cd /opt/splunk/etc/apps/config_explorer/

sudo mkdir /opt/splunk/etc/apps/config_explorer/local


echo "
[global]
# set for sc4s4rookies
write_access = true

hide_settings = true

" > /opt/splunk/etc/apps/config_explorer/local/config_explorer.conf


# enable the http input function on the node

mkdir /opt/splunk/etc/apps/splunk_httpinput/local/

echo "
## Created with JB Splunk Install script by magic
#enable the http input function on the node (disabled by default)
[http]
disabled = 0
enableSSL = 1

[http://sc4s4rookies]
disabled = 0
host = sc4s4roookieshec
token = $HEC_TOKEN

" > /opt/splunk/etc/apps/splunk_httpinput/local/inputs.conf

mkdir /opt/splunk/etc/system/local/

# enable defualt all index search to help attendees

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

sudo /opt/splunk/bin/splunk restart

################################################################################################################
## Add sc4s  ####
################################################################################################################

echo "${yellow}Time for some SC4S baby!${reset}"

echo "${yellow}Check date and TZ below!${reset}"
date 

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
Environment=\"SC4S_IMAGE=ghcr.io/splunk/splunk-connect-for-syslog/container:1\"

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
sudo mkdir /opt/splunk/sc4s/local 
sudo mkdir /opt/splunk/sc4s/archive 
sudo mkdir /opt/splunk/sc4s/tls

# SET CORRECT URL AND HEC TOKEN HERE
echo "
## Created with JB Splunk Install script by magic

# Output config
# URL to send syslog too

SC4S_DEST_SPLUNK_HEC_DEFAULT_URL=$HEC_URL

# HEC token        

SC4S_DEST_SPLUNK_HEC_DEFAULT_TOKEN=$HEC_TOKEN

#Uncomment the following line if using untrusted SSL certificates
SC4S_DEST_SPLUNK_HEC_TLS_VERIFY=no

# TLS Config, if needed
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
sleep 1
sudo systemctl stop sc4s

# Set ownership so configexplorer can edit the files as Splunk user

sudo chown -R splunk:splunk /opt/splunk

sudo systemctl restart rsyslog

#sudo /opt/splunk/bin/splunk restart

sudo podman ps

sleep 30

dnf update -y

