#!/usr/bin/env bash
set -euo pipefail

SSD_ROOT="/mnt/ssd"
CURRENT_USER="${SUDO_USER:-$USER}"

if [[ ! -d "${SSD_ROOT}" ]]; then
  echo "Missing ${SSD_ROOT}. Mount the SSD first."
  exit 1
fi

sudo mkdir -p \
  "${SSD_ROOT}/postgres" \
  "${SSD_ROOT}/redis" \
  "${SSD_ROOT}/nextcloud/app" \
  "${SSD_ROOT}/nextcloud/data" \
  "${SSD_ROOT}/backups"

sudo chown -R 999:999 "${SSD_ROOT}/postgres" "${SSD_ROOT}/redis"
sudo chown -R "${CURRENT_USER}:${CURRENT_USER}" "${SSD_ROOT}/backups" "${SSD_ROOT}/nextcloud"

echo "SSD directories are ready under ${SSD_ROOT}."
