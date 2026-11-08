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

  if check_for_gh_release "open-terminal" "open-webui/open-terminal"; then
    msg_info "Stopping Open Terminal"
    systemctl stop open-terminal
    msg_ok "Stopped Open Terminal"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "open-terminal" "open-webui/open-terminal" "tarball" "$CHECK_UPDATE_RELEASE"

    msg_info "Updating Open Terminal"
    cd /opt/open-terminal || exit 1
    $STD uv venv --python 3.12 .venv
    $STD uv pip install --python .venv/bin/python .
    msg_ok "Updated Open Terminal"

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
echo -e "${INFO}${YW}Open Terminal API key: /opt/open-terminal_data/.env${CL}"
