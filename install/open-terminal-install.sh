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

PYTHON_VERSION="3.12" setup_uv

fetch_and_deploy_gh_release "open-terminal" "open-webui/open-terminal" "tarball"

msg_info "Installing Open Terminal"
cd /opt/open-terminal || exit 1
$STD uv venv --python 3.12 .venv
$STD uv pip install --python .venv/bin/python .
msg_ok "Installed Open Terminal"

msg_info "Configuring Open Terminal"
mkdir -p /opt/open-terminal_data
install -m 600 /dev/null /opt/open-terminal_data/.env
cat <<EOF >/opt/open-terminal_data/.env
OPEN_TERMINAL_API_KEY=$(random_password 48)
OPEN_TERMINAL_MULTI_USER=false
OPEN_TERMINAL_ENABLE_BROWSER=false
OPEN_TERMINAL_ENABLE_DESKTOP=false
OPEN_TERMINAL_ENABLE_NOTEBOOKS=false
EOF
msg_ok "Configured Open Terminal"

msg_info "Creating Open Terminal Service"
cat <<'EOF' >/etc/systemd/system/open-terminal.service
[Unit]
Description=Open Terminal Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/open-terminal_data
Environment=HOME=/opt/open-terminal_data
Environment=SHELL=/bin/bash
Environment=PATH=/opt/open-terminal/.venv/bin:/opt/open-terminal_data/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=/opt/open-terminal_data/.env
ExecStartPre=/bin/sh -c 'test -n "$$OPEN_TERMINAL_API_KEY"'
ExecStart=/opt/open-terminal/.venv/bin/open-terminal run --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now open-terminal
$STD curl -fsS --retry 30 --retry-connrefused --retry-delay 1 --retry-max-time 60 --max-time 2 -o /dev/null http://127.0.0.1:8000/health
msg_ok "Created Open Terminal Service"

motd_ssh
customize
cleanup_lxc
