#!/usr/bin/env
# backup.sh — Daily backup for Nextcloud stack
# Output: single compressed archive per day at /mnt/ssd/backups/YYYY-MM-DD_HH-MM.tar.gz
# Usage: Run manually — see README Step 12

set -euo pipefail

# ── Resolve paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${PROJECT_DIR}/.env"

# ── Variables ─────────────────────────────────────────────────────────────────
TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
BACKUP_ROOT="/mnt/ssd/backups"
STAGING_DIR="/tmp/nextcloud-backup-${TIMESTAMP}"
ARCHIVE="${BACKUP_ROOT}/${TIMESTAMP}.tar.gz"
NC_APP_DIR="/mnt/ssd/nextcloud/app"

echo "=== Nextcloud Backup: ${TIMESTAMP} ==="

# ── 0. Skip if already ran today ──────────────────────────────────────────────
EXISTING=$(find "${BACKUP_ROOT}" -maxdepth 1 -name "${TODAY}_*.tar.gz" | head -1)
if [[ -n "${EXISTING}" ]]; then
  echo "      ↷ Backup already exists for today: $(basename "${EXISTING}")"
  echo "      ↷ Skipping — delete it manually to force a re-run."
  exit 0
fi

# ── 1. Disk space check ───────────────────────────────────────────────────────
DISK_USAGE=$(df "${BACKUP_ROOT}" | awk 'NR==2 {print $5}' | tr -d '%')
if [[ "${DISK_USAGE}" -gt 85 ]]; then
  echo "!!! SSD usage is ${DISK_USAGE}% — too full to back up safely"
  exit 1
fi
echo "      ✓ Disk usage: ${DISK_USAGE}%"

# ── 2. Create staging directory ───────────────────────────────────────────────
mkdir -p "${STAGING_DIR}"

# ── 3. Dump PostgreSQL ────────────────────────────────────────────────────────
echo "[1/3] Dumping PostgreSQL..."
docker exec nc-db pg_dump \
  -U nextcloud \
  --format=custom \
  --compress=9 \
  nextcloud \
  > "${STAGING_DIR}/nextcloud_db.dump"

DB_SIZE=$(stat -c%s "${STAGING_DIR}/nextcloud_db.dump")
if [[ "${DB_SIZE}" -lt 10240 ]]; then
  echo "!!! DB dump is only ${DB_SIZE} bytes — something went wrong"
  rm -rf "${STAGING_DIR}"
  exit 1
fi
echo "      ✓ DB dump saved ($(du -h "${STAGING_DIR}/nextcloud_db.dump" | cut -f1))"

# ── 4. Back up config.php ─────────────────────────────────────────────────────
echo "[2/3] Backing up config.php..."
cp "${NC_APP_DIR}/config/config.php" "${STAGING_DIR}/config.php"
echo "      ✓ config.php saved"

# ── 5. Back up project files ──────────────────────────────────────────────────
echo "[3/3] Backing up project files..."
tar -czf "${STAGING_DIR}/project.tar.gz" \
  --exclude="$(basename "${PROJECT_DIR}")/.git" \
  -C "$(dirname "${PROJECT_DIR}")" \
  "$(basename "${PROJECT_DIR}")"
echo "      ✓ Project archive saved"

# ── 6. Compress everything into a single archive ──────────────────────────────
echo "Compressing snapshot..."
tar -czf "${ARCHIVE}" \
  -C "$(dirname "${STAGING_DIR}")" \
  "$(basename "${STAGING_DIR}")"
rm -rf "${STAGING_DIR}"
echo "      ✓ Snapshot saved: $(basename "${ARCHIVE}") ($(du -h "${ARCHIVE}" | cut -f1))"

# ── 7. Prune archives older than 14 days ──────────────────────────────────────
echo "Pruning archives older than 14 days..."
find "${BACKUP_ROOT}" -maxdepth 1 -name "????-??-??_*.tar.gz" -mtime +14 -delete
echo "      ✓ Old archives pruned"

echo "=== Backup complete: ${ARCHIVE} ==="