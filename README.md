# Nextcloud on Raspberry Pi 4

Self-hosted Nextcloud on a Raspberry Pi with Docker Compose, an SSD-backed data layout, and a Cloudflare Tunnel. This version avoids manual `config.php` editing by applying runtime config through `occ`.

## Stack

- `nc-app`: Nextcloud web app
- `nc-db`: PostgreSQL database
- `nc-redis`: Redis cache and file locking
- `nc-cron`: Nextcloud background jobs
- `nc-cloudflared`: Cloudflare Tunnel

## Project Layout

```text
pi-nextcloud/
├── docker-compose.yml
├── .env.example
├── README.md
├── scripts/
│   ├── setup-pi.sh
│   ├── init-folders.sh
│   ├── configure-nextcloud.sh
│   ├── backup.sh
│   ├── restore.sh
│   ├── verify.sh
│   └── install-backup-timer.sh
└── systemd/
    ├── nextcloud-backup.service
    └── nextcloud-backup.timer
```

## Requirements

- Raspberry Pi OS Lite 64-bit
- Raspberry Pi 4 with an SSD mounted at `/mnt/ssd`
- Docker and Docker Compose plugin
- Cloudflare account and tunnel token

## Quick Start

1. Clone the repo and create your env file.

   ```bash
   git clone https://github.com/your-username/pi-nextcloud.git ~/code/pi-nextcloud
   cd ~/code/pi-nextcloud
   cp .env.example .env
   nano .env
   ```

2. Prepare the host.

   ```bash
   chmod +x scripts/*.sh
   ./scripts/setup-pi.sh
   ```

3. Start the stack.

   ```bash
   docker compose up -d
   ```

4. Apply Nextcloud configuration safely.

   ```bash
   ./scripts/configure-nextcloud.sh
   ```

5. Verify the deployment.

   ```bash
   ./scripts/verify.sh
   ```

## Why `occ` Instead of Editing `config.php`

Nextcloud generates `config.php` on first boot. Editing that PHP array by hand is brittle: it is easy to insert settings into the wrong nested array or create duplicate keys. `scripts/configure-nextcloud.sh` uses `docker exec ... php occ config:system:set` so the file is updated consistently.

## Backups

Run an on-demand backup:

```bash
./scripts/backup.sh
```

Install the daily systemd timer:

```bash
./scripts/install-backup-timer.sh
```

What the backup includes:

- PostgreSQL dump
- live `config.php`
- repo files, including `.env`

What it does not include:

- user files in `${NEXTCLOUD_DATA_DIR}`

Back up the data directory separately with `rclone`, snapshots, or another file-level backup method.

## Restore

Restore from an archive:

```bash
./scripts/restore.sh /mnt/ssd/backups/YYYY-MM-DD_HH-MM.tar.gz
```

This restores the database and `config.php`. Restore user files separately if needed, then run:

```bash
docker exec -u www-data nc-app php occ files:scan --all
```

## Useful Commands

```bash
docker compose ps
docker compose logs -f app
docker exec -u www-data nc-app php occ status
./scripts/verify.sh
```
