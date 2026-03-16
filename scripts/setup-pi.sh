#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_OVERRIDE_DIR="/etc/systemd/system/docker.service.d"
DOCKER_OVERRIDE_FILE="${DOCKER_OVERRIDE_DIR}/override.conf"
SYSCTL_DROPIN="/etc/sysctl.d/99-nextcloud.conf"

sudo apt update
sudo apt install -y ca-certificates curl git jq

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

sudo usermod -aG docker "${SUDO_USER:-$USER}" || true
sudo mkdir -p "${DOCKER_OVERRIDE_DIR}"
sudo tee "${DOCKER_OVERRIDE_FILE}" >/dev/null <<'UNIT'
[Unit]
After=mnt-ssd.mount
Requires=mnt-ssd.mount
UNIT

sudo tee "${SYSCTL_DROPIN}" >/dev/null <<'SYSCTL'
vm.overcommit_memory=1
net.core.rmem_max=7500000
net.core.wmem_max=7500000
SYSCTL

sudo systemctl daemon-reload
sudo sysctl --system >/dev/null
sudo systemctl enable docker containerd

"${PROJECT_DIR}/scripts/init-folders.sh"

echo "Pi host preparation complete. Log out and back in if Docker group membership was just added."
