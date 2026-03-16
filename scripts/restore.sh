#!/usr/bin/env
# restore.sh — Restore Nextcloud from a compressed backup archive
# Usage: ./scripts/restore.sh /mnt/ssd/backups/2026-03-15_02-00.tar.gz

set -euo pipefail

ARCHIVE="${1:-}"

if [[ -z "${ARCHIVE}" || ! -f "${ARCHIVE}" ]]; then
  echo "Usage: $0 /mnt/ssd/backups/<timestamp>.tar.gz"
  echo ""
  echo "Available backups:"
  ls /mnt/ssd/backups/*.tar.gz 2>/dev/null || echo "  (none found)"
  exit 1
fi

echo "=== Nextcloud Restore from: $(basename "${ARCHIVE}") ==="
echo "WARNING: This will overwrite the current database and config.php."
read -rp "Continue? [y/N] " confirm
[[ "${confirm}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── 1. Extract archive to temp dir ────────────────────────────────────────────
STAGING_DIR=$(mktemp -d)
echo "[1/5] Extracting archive..."
tar -xzf "${ARCHIVE}" -C "${STAGING_DIR}"
BACKUP_DIR=$(find "${STAGING_DIR}" -mindepth 1 -maxdepth 1 -type d | head -1)
echo "      ✓ Extracted to ${BACKUP_DIR}"

NC_APP_DIR="/mnt/ssd/nextcloud/app"

# ── 2. Stop the stack ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[2/5] Stopping stack..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" down
echo "      ✓ Stack stopped"

# ── 3. Restore PostgreSQL ─────────────────────────────────────────────────────
echo "[3/5] Restoring PostgreSQL..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" up -d db
sleep 5

docker exec -i nc-db psql -U nextcloud -c "DROP DATABASE IF EXISTS nextcloud;"
docker exec -i nc-db psql -U nextcloud -c "CREATE DATABASE nextcloud OWNER nextcloud;"
docker exec -i nc-db pg_restore \
  -U nextcloud \
  -d nextcloud \
  --no-owner \
  --role=nextcloud \
  < "${BACKUP_DIR}/nextcloud_db.dump"
echo "      ✓ Database restored"

# ── 4. Restore config.php ─────────────────────────────────────────────────────
echo "[4/5] Restoring config.php..."
mkdir -p "${NC_APP_DIR}/config"
cp "${BACKUP_DIR}/config.php" "${NC_APP_DIR}/config/config.php"
echo "      ✓ config.php restored"

# ── 5. Restart the full stack ─────────────────────────────────────────────────
echo "[5/5] Starting stack..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" up -d
echo "      ✓ Stack started"

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "${STAGING_DIR}"

echo ""
echo "=== Restore complete ==="
echo "Visit your Nextcloud URL and verify everything looks correct."
echo "If you see file mismatches, run:"
echo "  docker exec -u www-data nc-app php occ files:scan --all"