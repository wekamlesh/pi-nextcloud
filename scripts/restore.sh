#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_DIR}/.env"

ARCHIVE="${1:-}"
if [[ -z "${ARCHIVE}" || ! -f "${ARCHIVE}" ]]; then
  echo "Usage: $0 /mnt/ssd/backups/<timestamp>.tar.gz"
  exit 1
fi

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGING_DIR}"' EXIT

echo "WARNING: This will overwrite the current database and config.php."
echo "User data in ${NEXTCLOUD_DATA_DIR} is not restored by this script."
read -rp "Continue? [y/N] " confirm
[[ "${confirm}" =~ ^[Yy]$ ]] || exit 0

tar -xzf "${ARCHIVE}" -C "${STAGING_DIR}"
BACKUP_DIR="$(find "${STAGING_DIR}" -mindepth 1 -maxdepth 1 -type d | head -1)"

tar -xzf "${BACKUP_DIR}/project.tar.gz" -C "${STAGING_DIR}"

docker compose -f "${PROJECT_DIR}/docker-compose.yml" down

docker compose -f "${PROJECT_DIR}/docker-compose.yml" up -d db
for _ in {1..20}; do
  if docker exec nc-db pg_isready -U "${POSTGRES_USER}" -d postgres >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

docker exec -i nc-db psql -U "${POSTGRES_USER}" -d postgres -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};"
docker exec -i nc-db psql -U "${POSTGRES_USER}" -d postgres -c "CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};"
docker exec -i nc-db pg_restore \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  --no-owner \
  < "${BACKUP_DIR}/nextcloud_db.dump"

mkdir -p "${NEXTCLOUD_APP_DIR}/config"
cp "${BACKUP_DIR}/config.php" "${NEXTCLOUD_APP_DIR}/config/config.php"

docker compose -f "${PROJECT_DIR}/docker-compose.yml" up -d

echo "Restore complete. If user files were restored separately, run:"
echo "docker exec -u www-data nc-app php occ files:scan --all"
