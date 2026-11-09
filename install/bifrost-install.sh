#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: J0113
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/maximhq/bifrost

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

bifrost_tag=$(get_latest_gh_tag "maximhq/bifrost" "transports/")
bifrost_version="${bifrost_tag#transports/}"
tmp_dir=$(mktemp -d)

msg_info "Downloading Bifrost ${bifrost_version}"
CURL_TIMEOUT=600 curl_with_retry "https://downloads.getmaxim.ai/bifrost/${bifrost_version}/linux/$(arch_resolve "amd64" "arm64")/bifrost-http" "$tmp_dir/bifrost-http"
CURL_TIMEOUT=600 curl_with_retry "https://downloads.getmaxim.ai/bifrost/${bifrost_version}/linux/$(arch_resolve "amd64" "arm64")/bifrost-http.sha256" "$tmp_dir/bifrost-http.sha256"
(cd "$tmp_dir" && sha256sum -c bifrost-http.sha256) || {
  rm -rf "$tmp_dir"
  msg_error "The downloaded Bifrost release failed checksum verification."
  exit 1
}
mkdir -p /opt/bifrost /opt/bifrost_data
install -m 0755 "$tmp_dir/bifrost-http" /opt/bifrost/bifrost-http
rm -rf "$tmp_dir"
echo "$bifrost_tag" >~/.bifrost
msg_ok "Installed Bifrost ${bifrost_version}"

msg_info "Configuring Bifrost"
install -m 0600 /dev/null /opt/bifrost_data/.env
cat <<EOF >/opt/bifrost_data/.env
BIFROST_ENCRYPTION_KEY=$(random_password 64)
BIFROST_SETUP_TOKEN=$(random_password 64)
BIFROST_ADMIN_USERNAME=admin
BIFROST_ADMIN_PASSWORD=$(random_password 20)Aa1!
EOF
cat <<'EOF' >/opt/bifrost_data/config.json
{
  "$schema": "https://www.getbifrost.ai/schema",
  "encryption_key": "env.BIFROST_ENCRYPTION_KEY",
  "setup_token": "env.BIFROST_SETUP_TOKEN",
  "client": {
    "enforce_auth_on_inference": true
  },
  "governance": {
    "auth_config": {
      "is_enabled": true,
      "admin_username": "env.BIFROST_ADMIN_USERNAME",
      "admin_password": "env.BIFROST_ADMIN_PASSWORD"
    }
  }
}
EOF
msg_ok "Configured Bifrost"

msg_info "Starting Bifrost"
cat <<'EOF' >/etc/systemd/system/bifrost.service
[Unit]
Description=Bifrost AI Gateway
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bifrost
EnvironmentFile=/opt/bifrost_data/.env
ExecStart=/opt/bifrost/bifrost-http -app-dir /opt/bifrost_data -host 0.0.0.0 -port 8080 -log-style json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now bifrost

deadline=$((SECONDS + 120))
until curl -fsS --max-time 5 http://127.0.0.1:8080/health 2>/dev/null | jq -e '.status == "ok"' >/dev/null; do
  if ((SECONDS >= deadline)); then
    msg_error "Bifrost did not become ready. Check journalctl -u bifrost."
    exit 1
  fi
  sleep 2
done
msg_ok "Started Bifrost"

motd_ssh
customize
cleanup_lxc
