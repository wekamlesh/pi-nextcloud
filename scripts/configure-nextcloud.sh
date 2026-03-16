#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_DIR}/.env"

FIRST_DOMAIN="${NEXTCLOUD_TRUSTED_DOMAINS%%,*}"
FIRST_DOMAIN="${FIRST_DOMAIN%% *}"
TRUSTED_PROXY_1="${TRUSTED_PROXIES%%,*}"

occ() {
  docker exec -u www-data nc-app php occ "$@"
}

for _ in {1..40}; do
  if occ status >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

occ status >/dev/null
occ config:system:set trusted_domains 1 --value="${FIRST_DOMAIN}"
occ config:system:set overwriteprotocol --value=https
occ config:system:set overwrite.cli.url --value="${NEXTCLOUD_OVERWRITE_CLI_URL}"
occ config:system:set default_phone_region --value="${DEFAULT_PHONE_REGION}"
occ config:system:set log_type --value=file
occ config:system:set logfile --value="/var/www/html/data/nextcloud.log"
occ config:system:set loglevel --type=integer --value=2
occ config:system:set memcache.local --value='\\OC\\Memcache\\APCu'
occ config:system:set memcache.distributed --value='\\OC\\Memcache\\Redis'
occ config:system:set memcache.locking --value='\\OC\\Memcache\\Redis'
occ config:system:set redis host --value=redis
occ config:system:set redis port --type=integer --value=6379
occ config:system:set redis password --value="${REDIS_PASSWORD}"
occ config:system:set trusted_proxies 0 --value="${TRUSTED_PROXY_1}"
occ db:add-missing-indices || true

echo "Nextcloud configuration has been applied via occ."
