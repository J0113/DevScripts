#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: J0113
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/open-webui/open-terminal

APP="Open-Terminal"
var_tags="${var_tags:-ai;terminal;files}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/open-terminal ]]; then
    msg_error "No Open Terminal Installation Found!"
    exit 1
  fi

  if check_for_gh_release "open-terminal" "open-webui/open-terminal" ||
    [[ ! -f /etc/open-terminal/open-terminal.env ]] ||
    ! grep -qx 'User=open-terminal' /etc/systemd/system/open-terminal.service; then
    msg_info "Stopping Open Terminal"
    systemctl stop open-terminal
    msg_ok "Stopped Open Terminal"

    umask 022
    # Re-deploy the stable release too when migrating an existing root service.
    CLEAN_INSTALL=1 FORCE_UPDATE=1 fetch_and_deploy_gh_release "open-terminal" "open-webui/open-terminal" "tarball" "${CHECK_UPDATE_RELEASE:-latest}"

    export UV_PYTHON_INSTALL_DIR=/opt/open-terminal-python
    export UV_PYTHON_BIN_DIR=/opt/open-terminal-python/bin
    PYTHON_VERSION="3.12" setup_uv

    msg_info "Updating Open Terminal"
    cd /opt/open-terminal || exit 1
    $STD uv venv --clear --python 3.12 .venv
    $STD uv pip install --python .venv/bin/python .
    chmod -R go=rX /opt/open-terminal /opt/open-terminal-python
    msg_ok "Updated Open Terminal"

    msg_info "Securing Open Terminal"
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
    chown root:root /etc/open-terminal/open-terminal.env
    chmod 600 /etc/open-terminal/open-terminal.env
    chown -hR open-terminal:open-terminal /opt/open-terminal_data
    chmod 700 /opt/open-terminal_data
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
    msg_ok "Secured Open Terminal"

    msg_info "Starting Open Terminal"
    systemctl start open-terminal
    $STD curl -fsS --retry 30 --retry-connrefused --retry-delay 1 --retry-max-time 60 --max-time 2 -o /dev/null http://127.0.0.1:8000/health
    msg_ok "Started Open Terminal"
    msg_ok "Updated Open Terminal successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
echo -e "${INFO}${YW}Open Terminal API key: /etc/open-terminal/open-terminal.env${CL}"
