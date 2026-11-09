#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: J0113
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/maximhq/bifrost

APP="Bifrost"
var_tags="${var_tags:-ai;llm;gateway}"
var_cpu="${var_cpu:-1}"
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

  if [[ ! -f /opt/bifrost/bifrost-http ]]; then
    msg_error "No Bifrost Installation Found!"
    exit 1
  fi

  if check_for_gh_tag "bifrost" "maximhq/bifrost" "transports/"; then
    local tmp_dir
    tmp_dir=$(mktemp -d)
    CURL_TIMEOUT=600 curl_with_retry "https://downloads.getmaxim.ai/bifrost/${CHECK_UPDATE_RELEASE#transports/}/linux/$(arch_resolve "amd64" "arm64")/bifrost-http" "$tmp_dir/bifrost-http"
    CURL_TIMEOUT=600 curl_with_retry "https://downloads.getmaxim.ai/bifrost/${CHECK_UPDATE_RELEASE#transports/}/linux/$(arch_resolve "amd64" "arm64")/bifrost-http.sha256" "$tmp_dir/bifrost-http.sha256"
    if ! (cd "$tmp_dir" && sha256sum -c bifrost-http.sha256); then
      rm -rf "$tmp_dir"
      msg_error "The downloaded Bifrost release failed checksum verification."
      exit 1
    fi

    install -m 0755 "$tmp_dir/bifrost-http" /opt/bifrost/bifrost-http.new
    rm -rf "$tmp_dir"

    create_backup /opt/bifrost_data/.env /opt/bifrost_data/config.json

    msg_info "Stopping Bifrost"
    systemctl stop bifrost
    msg_ok "Stopped Bifrost"

    cp -a /opt/bifrost/bifrost-http /opt/bifrost/bifrost-http.previous
    mv -f /opt/bifrost/bifrost-http.new /opt/bifrost/bifrost-http

    msg_info "Starting Bifrost"
    if ! systemctl start bifrost; then
      mv -f /opt/bifrost/bifrost-http.previous /opt/bifrost/bifrost-http
      systemctl start bifrost
      msg_error "Bifrost did not start after the update. The previous binary was restored."
      exit 1
    fi
    deadline=$((SECONDS + 120))
    until curl -fsS --max-time 5 http://127.0.0.1:8080/health 2>/dev/null | jq -e '.status == "ok"' >/dev/null; do
      if ((SECONDS >= deadline)); then
        mv -f /opt/bifrost/bifrost-http.previous /opt/bifrost/bifrost-http
        systemctl restart bifrost
        msg_error "Bifrost did not start after the update. The previous binary was restored."
        exit 1
      fi
      sleep 2
    done
    rm -f /opt/bifrost/bifrost-http.previous
    echo "$CHECK_UPDATE_RELEASE" >~/.bifrost
    msg_ok "Started Bifrost"
    msg_ok "Updated Bifrost successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}Bifrost setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW}Admin password: /opt/bifrost_data/.env${CL}"
