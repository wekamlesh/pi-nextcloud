#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_DIR}/.env"

status=0

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "[PASS] ${description}"
  else
    echo "[FAIL] ${description}"
    status=1
  fi
}

check "SSD mount exists" mountpoint -q /mnt/ssd
check "Docker daemon is reachable" docker info
check "Compose config is valid" docker compose -f "${PROJECT_DIR}/docker-compose.yml" config
check "Nextcloud app container is running" docker ps --filter name=^/nc-app$ --filter status=running
check "Postgres container is running" docker ps --filter name=^/nc-db$ --filter status=running
check "Redis container is running" docker ps --filter name=^/nc-redis$ --filter status=running
check "Cron container is running" docker ps --filter name=^/nc-cron$ --filter status=running
check "Cloudflared container is running" docker ps --filter name=^/nc-cloudflared$ --filter status=running
check "Nextcloud responds to occ status" docker exec -u www-data nc-app php occ status
check "Backup root exists" test -d "${BACKUP_ROOT}"

latest_backup="$(find "${BACKUP_ROOT}" -maxdepth 1 -name '????-??-??_*.tar.gz' | sort | tail -1 || true)"
if [[ -n "${latest_backup}" ]]; then
  echo "[INFO] Latest backup: ${latest_backup}"
else
  echo "[WARN] No backup archive found in ${BACKUP_ROOT}"
fi

exit "${status}"
