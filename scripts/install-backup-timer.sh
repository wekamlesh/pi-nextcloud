#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_TARGET="/etc/systemd/system/nextcloud-backup.service"
TIMER_TARGET="/etc/systemd/system/nextcloud-backup.timer"
TMP_SERVICE="$(mktemp)"
trap 'rm -f "${TMP_SERVICE}"' EXIT

sed "s#__PROJECT_DIR__#${PROJECT_DIR}#g" \
  "${PROJECT_DIR}/systemd/nextcloud-backup.service" > "${TMP_SERVICE}"

sudo cp "${TMP_SERVICE}" "${SERVICE_TARGET}"
sudo cp "${PROJECT_DIR}/systemd/nextcloud-backup.timer" "${TIMER_TARGET}"
sudo systemctl daemon-reload
sudo systemctl enable --now nextcloud-backup.timer
systemctl list-timers nextcloud-backup.timer --no-pager
