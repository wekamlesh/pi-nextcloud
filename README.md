# Nextcloud on Raspberry Pi 4

Self-hosted Nextcloud running on a Raspberry Pi 4 with an external SSD, Docker Compose, and a Cloudflare Tunnel for secure public HTTPS access — no open ports required.

---

## Stack

| Service | Image | Purpose |
| --- | --- | --- |
| `nc-app` | `nextcloud:32-apache` | Main application |
| `nc-db` | `postgres:17` | Database |
| `nc-redis` | `redis:8-alpine` | Cache + file locking |
| `nc-cron` | `nextcloud:32-apache` | Background jobs (every 5 min) |
| `nc-cloudflared` | `cloudflare/cloudflared:latest` | Secure tunnel — no open ports |

---

## Folder Layout

```
project root/                  ← clone this repo here
├── docker-compose.yml
├── .env                       ← secrets — never commit
├── .env.example               ← template — safe to commit
└── scripts/
    ├── backup.sh
    └── restore.sh

/mnt/ssd/                      ← external SSD (all persistent data)
├── postgres/
├── redis/
├── nextcloud/
│   ├── app/                   ← Nextcloud code + config
│   └── data/                  ← user files
└── backups/
    ├── 2026-03-15_02-00.tar.gz  ← compressed daily snapshots
    └── backup.log
```

---

## Requirements

- Raspberry Pi 4 (2 GB RAM minimum, 4 GB recommended)
- Raspberry Pi OS Lite 64-bit (fresh install)
- External SSD formatted as ext4
- Cloudflare account with a domain and a Tunnel token
- Docker + Docker Compose installed

---

## Setup Guide

### Step 1 — Flash & configure the OS

Flash **Raspberry Pi OS Lite (64-bit)** using Raspberry Pi Imager. In the imager settings, enable SSH and set your username/password before writing. Boot the Pi, SSH in, then update:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git
```

### Step 2 — Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

Verify:

```bash
docker --version
docker compose version
```

> ⚠️ Log out and back in for the docker group change to take effect.
> 

### Step 3 — Mount the SSD (boot-safe)

Find your SSD and its UUID:

```bash
lsblk                        # find your SSD — usually /dev/sda1
sudo blkid /dev/sda1         # copy the UUID value
```

Create the mount point and add to fstab:

```bash
sudo mkdir -p /mnt/ssd
sudo nano /etc/fstab
```

Add this line (replace UUID with yours):

```
UUID=your-uuid-here  /mnt/ssd  ext4  defaults,nofail,x-systemd.automount  0  2
```

Test the mount:

```bash
sudo systemctl daemon-reload
df -h | grep ssd             # should show your SSD mounted
```

### Step 4 — Make Docker wait for the SSD

Docker must not start until the SSD is mounted, otherwise containers will write to the Pi's SD card.

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo nano /etc/systemd/system/docker.service.d/override.conf
```

Paste:

```
[Unit]
After=mnt-ssd.mount
Requires=mnt-ssd.mount
```

Apply:

```bash
sudo systemctl daemon-reload
sudo systemctl enable docker
sudo systemctl enable containerd
```

### Step 5 — Fix Redis memory warning

```bash
sudo nano /etc/sysctl.conf
```

Add:

```
vm.overcommit_memory=1
net.core.rmem_max=7500000
net.core.wmem_max=7500000
```

Apply:

```bash
sudo sysctl -p
```

### Step 6 — Create data directories

```bash
sudo mkdir -p /mnt/ssd/postgres
sudo mkdir -p /mnt/ssd/redis
sudo mkdir -p /mnt/ssd/nextcloud/app
sudo mkdir -p /mnt/ssd/nextcloud/data
sudo mkdir -p /mnt/ssd/backups
```

Fix ownership so your user can write to them:

```bash
sudo chown -R $USER:$USER /mnt/ssd/backups
sudo chown -R $USER:$USER /mnt/ssd/nextcloud/app/config
```

### Step 7 — Clone the repo and configure

```bash
git clone https://github.com/your-username/nextcloud-stack.git ~/nextcloud-stack
cd ~/nextcloud-stack
cp .env.example .env
nano .env                    # fill in all CHANGE_ME values
```

### Step 8 — Start the stack

```bash
docker compose up -d
```

Check everything is running:

```bash
docker ps
docker logs nc-app --tail 30
```

> Allow 2–3 minutes for Nextcloud to initialise on first boot.
> 

### Step 9 — Configure the Cloudflare Tunnel

In [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) → Networks → Tunnels → your tunnel → Public Hostnames:

| Field | Value |
| --- | --- |
| Subdomain | `cloud` |
| Domain | `yourdomain.com` |
| Type | `HTTP` |
| URL | `http://nc-app:80` |

> The cloudflared container runs on the same Docker bridge network as nc-app so it can resolve container names directly.
> 

### Step 10 — Tune config.php

Edit `/mnt/ssd/nextcloud/app/config/config.php` and add inside the array:

```php
// Trusted proxy (Cloudflare tunnel subnet)
'trusted_proxies'   => ['172.0.0.0/8'],
'overwriteprotocol' => 'https',
'overwrite.cli.url' => 'https://cloud.yourdomain.com',

// Redis caching
'memcache.local'    => '\\OC\\Memcache\\Redis',
'memcache.locking'  => '\\OC\\Memcache\\Redis',
'redis' => [
    'host'     => 'redis',
    'port'     => 6379,
    'password' => 'your-redis-password-from-.env',
],

// Locale & logging
'default_phone_region' => 'IN',
'log_type'  => 'file',
'logfile'   => '/var/www/html/data/nextcloud.log',
'loglevel'  => 2,
```

Run the missing-indices fix:

```bash
docker exec -u www-data nc-app php occ db:add-missing-indices
```

### Step 11 — Switch background jobs to Cron

In the Nextcloud admin panel → **Basic Settings** → **Background Jobs** → select **Cron**.

### Step 12 — Enable backups

Make scripts executable:

```bash
chmod +x ~/nextcloud-stack/scripts/backup.sh
chmod +x ~/nextcloud-stack/scripts/restore.sh
```

Run a backup manually:

```bash
~/nextcloud-stack/scripts/backup.sh
```

---

## Backup Strategy

| Item | Backed up? | Notes |
| --- | --- | --- |
| PostgreSQL DB | ✅ | Full `pg_dump`, compressed into snapshot |
| config.php | ✅ | Nextcloud settings |
| Project files | ✅ | `docker-compose.yml`, `.env`, scripts |
| User files (data) | ⚠️ | Too large for daily full backup — use rclone |

### How it works

Each run produces a single compressed archive:

```
/mnt/ssd/backups/2026-03-15_02-00.tar.gz
```

Which contains:

```
2026-03-15_02-00/
├── nextcloud_db.dump     ← PostgreSQL full dump
├── config.php            ← Nextcloud config
└── project.tar.gz        ← docker-compose.yml + .env + scripts
```

The script skips if a backup already ran today, and prunes archives older than 14 days automatically.

### Optional — back up user files with rclone

```bash
sudo apt install rclone -y
rclone config                # set up a remote (NAS, S3, Google Drive, etc.)
```

Add to crontab (runs at 3am, after the DB backup):

```
0 3 * * * rclone sync /mnt/ssd/nextcloud/data your-remote:nextcloud-backup >> /mnt/ssd/backups/rclone.log 2>&1
```

---

## Disaster Recovery

If your Pi dies or you need to move to a new machine:

1. Install Docker on the new Pi (Steps 1–6 above)
2. Mount the SSD or restore `/mnt/ssd` from a backup
3. Clone this repo and restore `.env` from your backup
4. Run the restore script:

```bash
chmod +x ~/nextcloud-stack/scripts/restore.sh
./scripts/restore.sh /mnt/ssd/backups/2026-03-15_02-00.tar.gz
```

Your Cloudflare tunnel token stays the same — it reconnects automatically.

---

## Day-to-Day Commands

```bash
# Check status
docker ps

# View logs (follow)
docker logs nc-app --tail 50 -f

# Update all images
docker compose pull && docker compose up -d

# Run occ commands
docker exec -u www-data nc-app php occ <command>

# Scan user files (after restore)
docker exec -u www-data nc-app php occ files:scan --all

# Run a backup
~/nextcloud-stack/scripts/backup.sh

# Stop everything
docker compose down

# Full restart
docker compose down && docker compose up -d
```

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Nextcloud shows wrong URL / no HTTPS | Check `overwriteprotocol` and `overwrite.cli.url` in config.php |
| Redis connection error | Confirm `REDIS_PASSWORD` in `.env` matches `config.php` |
| Cloudflare tunnel can't reach app | Verify cloudflared is on the same Docker network as nc-app |
| Cloudflare Error 1033 | Check tunnel hostname in Zero Trust dashboard matches your domain |
| Files out of sync after restore | Run `occ files:scan --all` |
| Docker starts before SSD mounts | Check systemd override in `/etc/systemd/system/docker.service.d/override.conf` |
| DB performance warnings in admin | Run `occ db:add-missing-indices` |
| Backup permission denied | Run `sudo chown -R $USER:$USER /mnt/ssd/backups` |
| Backup skipped unexpectedly | A snapshot for today already exists — delete it to force a re-run |
