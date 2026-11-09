#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: J0113
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/open-webui/open-terminal

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Open Terminal Dependencies"
$STD apt install -y git
msg_ok "Installed Open Terminal Dependencies"

if systemctl is-active --quiet open-terminal; then
  systemctl stop open-terminal
fi

umask 022
export UV_PYTHON_INSTALL_DIR=/opt/open-terminal-python
export UV_PYTHON_BIN_DIR=/opt/open-terminal-python/bin
PYTHON_VERSION="3.12" setup_uv

fetch_and_deploy_gh_release "open-terminal" "open-webui/open-terminal" "tarball"

msg_info "Installing Open Terminal"
cd /opt/open-terminal || exit 1
$STD uv venv --clear --python 3.12 .venv
$STD uv pip install --python .venv/bin/python .
chmod -R go=rX /opt/open-terminal /opt/open-terminal-python
msg_ok "Installed Open Terminal"

msg_info "Configuring Open Terminal"
id -u open-terminal &>/dev/null || useradd --system --user-group --home-dir /opt/open-terminal_data --shell /bin/bash open-terminal
install -d -o root -g root -m 755 /etc/open-terminal
if [[ -f /opt/open-terminal_data/.env ]]; then
  if [[ -e /etc/open-terminal/open-terminal.env ]]; then
    if ! cmp -s /opt/open-terminal_data/.env /etc/open-terminal/open-terminal.env; then
      msg_error "Conflicting Open Terminal configuration files; resolve before updating"
      exit 1
    fi
  else
    install -o root -g root -m 600 /opt/open-terminal_data/.env /etc/open-terminal/open-terminal.env
  fi
  rm /opt/open-terminal_data/.env
fi
if [[ ! -e /etc/open-terminal/open-terminal.env ]]; then
  install -o root -g root -m 600 /dev/null /etc/open-terminal/open-terminal.env
  cat <<EOF >/etc/open-terminal/open-terminal.env
OPEN_TERMINAL_API_KEY=$(random_password 48)
OPEN_TERMINAL_MULTI_USER=false
OPEN_TERMINAL_ENABLE_BROWSER=false
OPEN_TERMINAL_ENABLE_DESKTOP=false
OPEN_TERMINAL_ENABLE_NOTEBOOKS=false
EOF
fi
chown root:root /etc/open-terminal/open-terminal.env
chmod 600 /etc/open-terminal/open-terminal.env
mkdir -p /opt/open-terminal_data
chown -hR open-terminal:open-terminal /opt/open-terminal_data
chmod 700 /opt/open-terminal_data
msg_ok "Configured Open Terminal"

msg_info "Creating Open Terminal Service"
cat <<'EOF' >/etc/systemd/system/open-terminal.service
[Unit]
Description=Open Terminal Service
After=network.target

[Service]
Type=simple
User=open-terminal
Group=open-terminal
WorkingDirectory=/opt/open-terminal_data
Environment=HOME=/opt/open-terminal_data
Environment=SHELL=/bin/bash
Environment=PATH=/opt/open-terminal/.venv/bin:/opt/open-terminal_data/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=/etc/open-terminal/open-terminal.env
ExecStartPre=/bin/sh -c 'test -n "$$OPEN_TERMINAL_API_KEY"'
ExecStart=/opt/open-terminal/.venv/bin/open-terminal run --host 0.0.0.0 --port 8000
NoNewPrivileges=yes
CapabilityBoundingSet=
UMask=0077
ProtectSystem=strict
InaccessiblePaths=/etc/open-terminal/open-terminal.env
ReadWritePaths=/opt/open-terminal_data
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictRealtime=yes
LockPersonality=yes
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now open-terminal
$STD curl -fsS --retry 30 --retry-connrefused --retry-delay 1 --retry-max-time 60 --max-time 2 -o /dev/null http://127.0.0.1:8000/health
msg_ok "Created Open Terminal Service"

motd_ssh
customize
cleanup_lxc
