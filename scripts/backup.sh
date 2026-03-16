#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_DIR}/.env"

TODAY="$(date +%Y-%m-%d)"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M)"
STAGING_DIR="/tmp/nextcloud-backup-${TIMESTAMP}"
ARCHIVE="${BACKUP_ROOT}/${TIMESTAMP}.tar.gz"
EXISTING="$(find "${BACKUP_ROOT}" -maxdepth 1 -name "${TODAY}_*.tar.gz" | head -1)"

mkdir -p "${BACKUP_ROOT}"

echo "=== Nextcloud Backup: ${TIMESTAMP} ==="

if [[ -n "${EXISTING}" ]]; then
  echo "Backup already exists for today: $(basename "${EXISTING}")"
  exit 0
fi

DISK_USAGE="$(df "${BACKUP_ROOT}" | awk 'NR==2 {print $5}' | tr -d '%')"
if [[ "${DISK_USAGE}" -gt 85 ]]; then
  echo "SSD usage is ${DISK_USAGE}% - too full to back up safely"
  exit 1
fi

mkdir -p "${STAGING_DIR}"

docker exec nc-db pg_dump \
  -U "${POSTGRES_USER}" \
  --format=custom \
  --compress=9 \
  "${POSTGRES_DB}" \
  > "${STAGING_DIR}/nextcloud_db.dump"

cp "${NEXTCLOUD_APP_DIR}/config/config.php" "${STAGING_DIR}/config.php"

tar -czf "${STAGING_DIR}/project.tar.gz" \
  --exclude='.git' \
  -C "$(dirname "${PROJECT_DIR}")" \
  "$(basename "${PROJECT_DIR}")"

tar -tzf "${STAGING_DIR}/project.tar.gz" >/dev/null

tar -czf "${ARCHIVE}" \
  -C "$(dirname "${STAGING_DIR}")" \
  "$(basename "${STAGING_DIR}")"

rm -rf "${STAGING_DIR}"
find "${BACKUP_ROOT}" -maxdepth 1 -name '????-??-??_*.tar.gz' -mtime +"${BACKUP_RETENTION_DAYS}" -delete

echo "Backup complete: ${ARCHIVE}"
