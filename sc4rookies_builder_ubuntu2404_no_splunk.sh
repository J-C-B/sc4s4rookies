#!/bin/bash
#
# Last updated: 2026-04-30 14:34 NZST
# Version 2.2.1
# sc4s4rookies — Ubuntu 24.04 builder (John Barnett)
#
# Purpose: Prepare a host for Splunk Connect for Syslog (SC4S) “4 rookies” style use—install Splunk apps/TAs,
# rsyslog forward to local :514, HEC input, and related Splunk-side defaults. Intended as a one-shot on a clean
# or lab system; review before production.
#
# Splunk handling:
#   • If /opt/splunk/bin/splunk exists: prompts to continue with SC4S4Rookies-only setup (no full Splunk install).
#   • If missing: prompts to either exit, or download and run the community Enterprise install script
#     (SPLUNK_SCRIPT_URL), then continues once the binary is present.
#
# Dependencies: Splunk app archives are fetched over HTTPS from GitHub raw (SC4S4ROOKIES_DEPS_BASE_URL), not
# bundled beside the script—so a standalone copy of this script still works after values are pushed to that branch.
# Optional Splunk installer download uses curl or wget.
#
# Run as root (sudo). Bash 4+ recommended (${var,,} for prompts).
#

# Set shell for splunk user if non-set (run as root)
#usermod -s /bin/bash splunk

################################################################################################################
## Designed to run once; assumes you understand changes to rsyslog, Splunk apps, and local listeners.        ####
################################################################################################################

# Set URL and Tokens here (export before running to override)
# Default HEC URL uses this host's name (not 127.0.0.1). Default Splunk certs often use CN SplunkServerDefaultCert,
# which still will not match the hostname — set SC4S_DEST_SPLUNK_HEC_DEFAULT_TLS_VERIFY=no in env_file (note DEFAULT;
# SC4S_DEST_SPLUNK_HEC_TLS_VERIFY without DEFAULT is ignored by SC4S).
_SC4S_HEC_HOST="$(hostname -f 2>/dev/null || true)"
[[ -z "${_SC4S_HEC_HOST}" ]] && _SC4S_HEC_HOST="$(hostname -s)"
: "${HEC_URL:=https://${_SC4S_HEC_HOST}:8088}"
unset _SC4S_HEC_HOST
HEC_TOKEN="e82f986a-7582-41f8-83c3-86c98ba278b6"

# Splunk app bundles under dependencies/ in this repo (GitHub raw). Override to use a fork, branch, or commit SHA.
# Example pin: SC4S4ROOKIES_DEPS_BASE_URL=https://raw.githubusercontent.com/J-C-B/sc4s4rookies/abc1234/dependencies
: "${SC4S4ROOKIES_DEPS_BASE_URL:=https://raw.githubusercontent.com/J-C-B/sc4s4rookies/main/dependencies}"

# Full Splunk install when /opt/splunk/bin/splunk is missing (override to pin branch or fork)
: "${SPLUNK_SCRIPT_URL:=https://raw.githubusercontent.com/J-C-B/community-splunk-scripts/master/enterprise-splunk-ubuntu2404.sh}"

################################################################################################################
################################################################################################################
########################## Further below, there be dragons - know what you are doing :) ########################
################################################################################################################
################################################################################################################
red=`tput setaf 1`
green=`tput setaf 2`
yellow=`tput setaf 3`
reset=`tput sgr0`

SPLUNK_BIN="/opt/splunk/bin/splunk"

echo ""
if [[ -x "${SPLUNK_BIN}" ]]; then
  echo "${green}Splunk is detected at ${SPLUNK_BIN}.${reset}"
  echo "${yellow}This run will only install SC4S4Rookies components (apps, TAs, and related config), not a full Splunk install.${reset}"
  while true; do
    read -r -p "${yellow}Continue? (y/n): ${reset}" yn
    case "${yn,,}" in
      y|yes) break ;;
      n|no) echo "${red}Aborted.${reset}"; exit 0 ;;
      *) echo "${red}Please enter y or n.${reset}" ;;
    esac
  done
else
  echo "${yellow}Splunk was not detected (${SPLUNK_BIN} is missing or not executable).${reset}"
  while true; do
    read -r -p "${yellow}Install Splunk first using the community enterprise script, then continue here? (y/n): ${reset}" yn
    case "${yn,,}" in
      n|no)
        echo "${red}You cannot install SC4S4Rookies without Splunk. Exiting.${reset}"
        exit 1
        ;;
      y|yes) break ;;
      *) echo "${red}Please enter y or n.${reset}" ;;
    esac
  done
  echo "${yellow}Downloading and running Splunk install script...${reset}"
  echo "${yellow}${SPLUNK_SCRIPT_URL}${reset}"
  SPLUNK_INSTALLER="$(mktemp)"
  _dl_ok=0
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${SPLUNK_INSTALLER}" "${SPLUNK_SCRIPT_URL}" && _dl_ok=1
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "${SPLUNK_INSTALLER}" "${SPLUNK_SCRIPT_URL}" && _dl_ok=1
  else
    echo "${red}Need curl or wget to download the Splunk install script. Run: sudo apt-get install -y curl${reset}"
    rm -f "${SPLUNK_INSTALLER}"
    exit 1
  fi
  if [[ "${_dl_ok}" -ne 1 ]]; then
    echo "${red}Failed to download Splunk install script.${reset}"
    rm -f "${SPLUNK_INSTALLER}"
    exit 1
  fi
  # Patch out the blocking `multitail` tail at the end of the Splunk install script so this
  # wrapper script continues without waiting for user interaction.
  echo "${yellow}Patching Splunk install script to disable blocking multitail call...${reset}"
  sed -i 's|^\(multitail .*\)$|# [sc4s4rookies] non-interactive: \1|' "${SPLUNK_INSTALLER}"
  if ! bash "${SPLUNK_INSTALLER}"; then
    echo "${red}Splunk install script exited with an error.${reset}"
    rm -f "${SPLUNK_INSTALLER}"
    exit 1
  fi
  rm -f "${SPLUNK_INSTALLER}"
  if [[ ! -x "${SPLUNK_BIN}" ]]; then
    echo "${red}Splunk install finished but ${SPLUNK_BIN} is still missing or not executable. Exiting.${reset}"
    exit 1
  fi
  echo "${green}Splunk is now present. Continuing with SC4S4Rookies setup...${reset}"
fi
echo ""

#set local logs to go to sc4s

echo "
## Created with JB Splunk Install script by magic
*.* @127.0.0.1:514           # Use @ for UDP protocol
" >>  /etc/rsyslog.conf


echo "${yellow}Update and install packages${reset}"
#Update package lists

sudo apt update 
sudo apt install nano python3 -y

find /usr/share/nano -name '*.nanorc' -printf "include %p\n" > ~/.nanorc

################################################################################################################
## Install and setup Splunk  ####
################################################################################################################


########################## Adding the TAs

echo "${yellow}Adding the SC4S TAs${reset}"

mkdir /opt/deps
cd /opt/deps

# Rookies apps (SC4S TA + app; archives live in dependencies/ on GitHub)

wget "${SC4S4ROOKIES_DEPS_BASE_URL}/TA-sc4s-2.0.1.tar.gz"

wget "${SC4S4ROOKIES_DEPS_BASE_URL}/sc4s-4rookies-2.0.4.tar.gz"

wget "${SC4S4ROOKIES_DEPS_BASE_URL}/TA-sc4s-datagen-2.0.3.tar.gz"

########################## Splunk Apps and TAs

wget "${SC4S4ROOKIES_DEPS_BASE_URL}/config-explorer_1824.tar.gz"

wget "${SC4S4ROOKIES_DEPS_BASE_URL}/force-directed-app-for-splunk_311.tgz"

wget "${SC4S4ROOKIES_DEPS_BASE_URL}/infosec-app-for-splunk_171.tgz"

wget "${SC4S4ROOKIES_DEPS_BASE_URL}/splunk-app-for-lookup-file-editing_406.tgz"

wget "${SC4S4ROOKIES_DEPS_BASE_URL}/sankey-viz_100.tgz"

wget "${SC4S4ROOKIES_DEPS_BASE_URL}/splunk-add-on-for-cisco-asa_600.tgz"

wget "${SC4S4ROOKIES_DEPS_BASE_URL}/splunk-add-on-for-unix-and-linux_1020.tgz"

wget "${SC4S4ROOKIES_DEPS_BASE_URL}/splunk-common-information-model-cim_850.tgz"


if [[ ! -d /opt/splunk/etc/apps ]]; then
  echo "${red}/opt/splunk/etc/apps is missing. Splunk may not be installed correctly. Exiting.${reset}"
  exit 1
fi

echo "${yellow}Extracting Splunk apps into /opt/splunk/etc/apps ...${reset}"
shopt -s nullglob
for f in *.spl *.tgz *.tar.gz; do
  echo "${yellow}  ${f}${reset}"
  tar -xf "$f" -C /opt/splunk/etc/apps/
done
shopt -u nullglob

sudo chown -R splunk:splunk /opt/splunk

echo "${yellow}Setting the config explorer to hide settings and allow editing${reset}"

sudo mkdir -p /opt/splunk/etc/apps/config_explorer/local

echo "
[global]
# set for sc4s4rookies
write_access = true

hide_settings = true

" | sudo tee /opt/splunk/etc/apps/config_explorer/local/config_explorer.conf > /dev/null


# enable the http input function on the node

sudo mkdir -p /opt/splunk/etc/apps/splunk_httpinput/local/

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

" | sudo tee /opt/splunk/etc/apps/splunk_httpinput/local/inputs.conf > /dev/null

sudo mkdir -p /opt/splunk/etc/system/local/

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
" | sudo tee /opt/splunk/etc/system/local/authorize.conf > /dev/null

# enable data model acceleration for Splunk_SA_CIM, so info sec app can use the data models

mkdir /opt/splunk/etc/apps/Splunk_SA_CIM/local/

echo "
[Network_Traffic]
acceleration = 1
acceleration.manual_rebuilds = 1

[Network_Sessions]
acceleration = 1
acceleration.manual_rebuilds = 1

[Web]
acceleration = 1
acceleration.manual_rebuilds = 1

[Authentication]
acceleration = 1
acceleration.manual_rebuilds = 1
" | sudo tee /opt/splunk/etc/apps/Splunk_SA_CIM/local/datamodels.conf  > /dev/null


echo "${yellow}Starting Splunk - fire it up!! and enabling Splunk to start at boot time with user=splunk${reset}"

sudo chown -R splunk:splunk /opt/splunk

sudo /opt/splunk/bin/splunk restart

################################################################################################################
## Add sc4s  ####
################################################################################################################

echo "${yellow}Time for some SC4S baby!${reset}"

echo "${yellow}Check date and TZ below!${reset}"
date 

echo "${yellow}Install Conntrack${reset}"

sudo apt install -y conntrack

echo "${yellow}Install Podman${reset}"

# Ubuntu 22.04+ (including 24.04) ships podman in the archive. Do not use the old OpenSUSE Kubic testing
# repo here: it often has no Release file / bad key for new LTS, and apt-key is deprecated.
sudo rm -f /etc/apt/sources.list.d/devel:kubic:libcontainers:testing.list
sudo apt-get update -qq
if ! apt-cache show podman &>/dev/null; then
  echo "${yellow}Enabling universe component for podman package...${reset}"
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y universe
  sudo apt-get update -qq
fi
sudo apt-get install -y podman


echo "
## Edited with JB Splunk Install script by magic
net.core.rmem_default = 17039360
net.core.rmem_max = 17039360
" >> /etc/sysctl.conf

sysctl -p

echo "${yellow}sudoers: allow splunk user to manage sc4s and inspect the SC4S container${reset}"
# Use user splunk (not %splunk — that is the *group* named splunk). Ubuntu installs these under /usr/bin.
_SPLUNK_SUDO=/etc/sudoers.d/splunk-sc4s
sudo tee "${_SPLUNK_SUDO}" > /dev/null <<'EOF'
# sc4s4rookies: splunk user — sc4s unit + read-only podman (paths match Ubuntu 24.04)
splunk ALL=(root) NOPASSWD: /usr/bin/systemctl start sc4s, /usr/bin/systemctl stop sc4s, /usr/bin/systemctl restart sc4s, /usr/bin/systemctl status sc4s
splunk ALL=(root) NOPASSWD: /usr/bin/podman logs SC4S, /usr/bin/podman ps
EOF
sudo chmod 0440 "${_SPLUNK_SUDO}"
if ! sudo visudo -cf "${_SPLUNK_SUDO}"; then
  echo "${red}sudoers fragment failed visudo -cf; removing ${_SPLUNK_SUDO}${reset}"
  sudo rm -f "${_SPLUNK_SUDO}"
  exit 1
fi
unset _SPLUNK_SUDO

echo "
## Created with JB Splunk Install script by magic
[Unit]
Description=SC4S Container
Wants=NetworkManager.service network-online.target
After=NetworkManager.service network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Environment=\"SC4S_IMAGE=ghcr.io/splunk/splunk-connect-for-syslog/container3:latest\"

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
ExecStartPre=/usr/bin/bash -c \"/usr/bin/podman rm SC4S > /dev/null 2>&1 || true\"

ExecStart=/usr/bin/podman run \\
        -e \"SC4S_CONTAINER_HOST=\${SC4SHOST}\" \\
        -v \$SC4S_PERSIST_MOUNT \\
        -v \$SC4S_LOCAL_MOUNT \\
        -v \$SC4S_ARCHIVE_MOUNT \\
        -v \$SC4S_TLS_MOUNT \\
        --env-file=/opt/splunk/sc4s/env_file \\
        --health-cmd=\"/usr/sbin/syslog-ng-ctl healthcheck --timeout 5\" \\
        --health-interval=2m --health-retries=6 --health-timeout=5s \\
        --network host \\
        --name SC4S \\
        --rm \$SC4S_IMAGE

Restart=on-failure
" | sudo tee /lib/systemd/system/sc4s.service > /dev/null

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

# Disable TLS verify for HEC (required for default Splunk lab certs / CN mismatch); must be *_DEFAULT_* per Splunk docs
SC4S_DEST_SPLUNK_HEC_DEFAULT_TLS_VERIFY=no

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
ss -tulpn | grep LISTEN || true
sleep 1
sudo systemctl stop sc4s

# Set ownership so configexplorer can edit the files as Splunk user

sudo chown -R splunk:splunk /opt/splunk

sudo systemctl restart rsyslog

#sudo /opt/splunk/bin/splunk restart

sudo podman ps

sleep 30

sudo apt upgrade -y

