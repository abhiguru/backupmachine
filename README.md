# GuruColdStorage Backup System

A pull-based backup system for the GuruColdStorage Supabase application. The backup machine initiates all connections to the primary server, providing enhanced security - even if the primary server is compromised, attackers cannot delete backups.

## Architecture

```
┌─────────────────────┐         SSH/rsync          ┌─────────────────────┐
│   BACKUP MACHINE    │ ◄──────────────────────── │   PRIMARY SERVER    │
│  (192.168.0.130)    │        Pull backups        │  (172.16.194.128)   │
│                     │                            │                     │
│  /backup/           │                            │  PostgreSQL DB      │
│  ├── database/      │                            │  File Storage       │
│  ├── storage/       │                            │  Source Code        │
│  ├── source/        │                            │  Encrypted Secrets  │
│  ├── secrets/       │                            │                     │
│  └── logs/          │                            │                     │
└─────────────────────┘                            └─────────────────────┘
```

## Components

| Script | Purpose | Schedule |
|--------|---------|----------|
| `backup-orchestrator.sh` | Master script - runs all backups sequentially | Every 4 hours via cron |
| `pull-database.sh` | PostgreSQL dump from primary server | Called by orchestrator |
| `pull-source.sh` | Backup source code from 3 projects as tar.gz | Called by orchestrator |
| `pull-storage.sh` | rsync file storage (GRN images, PDFs, documents) | Called by orchestrator |
| `pull-secrets.sh` | rsync GPG-encrypted .env files | Called by orchestrator |
| `sync-to-secondary.sh` | Mirror backups to external drive | Called by orchestrator |
| `decrypt-env.sh` | Helper script to decrypt secrets for recovery | Manual use |

## Backup Details

### Database Backup (`pull-database.sh`)
- **Method**: Full PostgreSQL dump via SSH forced command
- **Retention**: 7 days (~42 restore points at 6 backups/day)
- **Compression**: gzip level 9 (maximum)
- **Integrity Check**: Verifies "PostgreSQL database dump complete" marker
- **Output**: `/backup/database/supabase_backup_YYYYMMDD_HHMMSS.sql.gz`

### File Storage Backup (`pull-storage.sh`)
- **Method**: rsync mirror with `--delete`
- **Retention**: Latest snapshot only (no versioning)
- **Content**: GRN images, PDFs, user-uploaded documents
- **Output**: `/backup/storage/`

### Source Code Backup (`pull-source.sh`)
- **Method**: rsync to staging, then tar.gz archive
- **Retention**: 7 days
- **Projects**:
  - `supabase` - GuruColdStorageSupabase
  - `react-web` - GuruColdStorageReactWebSupabase
  - `react-native` - GCSReactNative
- **Excludes**: node_modules, .next, dist, build, .git, docker/volumes, android/.gradle, ios/Pods, .expo
- **Output**: `/backup/source/{project}_backup_YYYYMMDD_HHMMSS.tar.gz`

### Secrets Backup (`pull-secrets.sh`)
- **Method**: rsync with GPG filter (*.gpg files only)
- **Retention**: 7 days
- **Encryption**: GPG symmetric encryption
- **Output**: `/backup/secrets/.env.YYYYMMDD_HHMMSS.gpg`

### Secondary Location Sync (`sync-to-secondary.sh`)
- **Method**: rsync mirror to external drive
- **Target**: `/media/abhinavguru/BACKUPS/GuruColdStorage-Backup/`
- **Behavior**: Skips gracefully if external drive not mounted
- **Content**: Full mirror of `/backup/` directory

## Cron Schedule

```bash
# Runs at: 00:00, 04:00, 08:00, 12:00, 16:00, 20:00
0 */4 * * * /home/abhinavguru/backup-scripts/backup-orchestrator.sh >> /backup/logs/cron.log 2>&1
```

## Directory Structure

```
/backup/
├── database/          # PostgreSQL dumps (7-day retention)
│   └── supabase_backup_YYYYMMDD_HHMMSS.sql.gz
├── source/            # Source code archives (7-day retention)
│   ├── supabase_backup_YYYYMMDD_HHMMSS.tar.gz
│   ├── react-web_backup_YYYYMMDD_HHMMSS.tar.gz
│   └── react-native_backup_YYYYMMDD_HHMMSS.tar.gz
├── source-staging/    # Staging area for source sync
├── storage/           # File storage mirror (latest snapshot)
│   └── [supabase storage buckets]
├── secrets/           # GPG-encrypted .env files (7-day retention)
│   └── .env.YYYYMMDD_HHMMSS.gpg
└── logs/              # All operation logs
    ├── cron.log
    ├── orchestrator.log
    ├── database-pull.log
    ├── source-pull.log
    ├── storage-pull.log
    ├── secrets-pull.log
    └── secondary-sync.log
```

## Security Features

| Feature | Description |
|---------|-------------|
| **Pull-Based Architecture** | Backup machine initiates connections; primary cannot delete backups |
| **SSH Forced Commands** | Primary server restricts SSH key to specific allowed operations |
| **Read-Only Access** | Backup user has read-only ACLs on primary server |
| **Lock File** | Prevents concurrent backup runs |
| **Encrypted Secrets** | .env files encrypted with GPG before transfer |
| **DR Team Isolation** | Separate restricted user for disaster recovery access |

## Disaster Recovery

### DR Team Access

A restricted `drteam` user exists for disaster recovery:

```bash
# Connect to backup machine
ssh -i ~/.ssh/dr_backup_key drteam@192.168.0.130

# List database backups
ssh -i ~/.ssh/dr_backup_key drteam@192.168.0.130 "ls -lh /backup/database/"

# Download latest database backup
scp -i ~/.ssh/dr_backup_key drteam@192.168.0.130:/backup/database/supabase_backup_YYYYMMDD_HHMMSS.sql.gz ./

# Sync all storage files
rsync -avz -e "ssh -i ~/.ssh/dr_backup_key" drteam@192.168.0.130:/backup/storage/ ./storage/
```

### Database Recovery

```bash
# Download and decompress
scp drteam@192.168.0.130:/backup/database/supabase_backup_YYYYMMDD_HHMMSS.sql.gz ./
gunzip supabase_backup_YYYYMMDD_HHMMSS.sql.gz

# Restore to PostgreSQL
psql -h localhost -U postgres -d supabase < supabase_backup_YYYYMMDD_HHMMSS.sql
```

### Secrets Recovery

```bash
# Decrypt on backup machine (passphrase stored locally)
ssh drteam@192.168.0.130 "/home/abhinavguru/backup-scripts/decrypt-env.sh /backup/secrets/.env.YYYYMMDD_HHMMSS.gpg" > .env

# Or decrypt locally (requires passphrase)
gpg --decrypt .env.YYYYMMDD_HHMMSS.gpg > .env
```

## Monitoring

### Check Backup Status

```bash
# View recent orchestrator activity
tail -50 /backup/logs/orchestrator.log

# Check last backup times
ls -lt /backup/database/ | head -5
ls -lt /backup/secrets/ | head -5

# Check storage size
du -sh /backup/storage/
```

### Log Files

| Log | Contents |
|-----|----------|
| `/backup/logs/orchestrator.log` | Summary of all backup runs |
| `/backup/logs/cron.log` | Full output from cron executions |
| `/backup/logs/database-pull.log` | Database backup details |
| `/backup/logs/source-pull.log` | Source code backup details |
| `/backup/logs/storage-pull.log` | File sync details with rsync stats |
| `/backup/logs/secrets-pull.log` | Secrets sync details |
| `/backup/logs/secondary-sync.log` | External drive sync details |

## Known Limitations

1. **Storage has no version history** - Uses rsync `--delete`, so deleted files on primary are deleted from backup
2. **No disk space monitoring** - Backups may fail if disk fills up

## SSH Configuration

The backup machine uses this SSH config (`~/.ssh/config`):

```
Host primary-server
    HostName 172.16.194.128
    User backupuser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

## Troubleshooting

### Backup Failing with SSH Timeout
- Check network connectivity: `ping 172.16.194.128`
- Verify SSH service on primary: `ssh primary-server "echo test"`
- Check firewall rules on primary server

### Database Backup Empty or Incomplete
- Check primary server disk space
- Verify PostgreSQL is running on primary
- Review `/backup/logs/database-pull.log` for errors

### Lock File Blocking Backups
```bash
# Check if backup is actually running
ps aux | grep backup-orchestrator

# If not running, remove stale lock
rm /tmp/backup-orchestrator.lock
```

## Expo Dev Server SSH Tunnel

An SSH tunnel is configured to forward the Expo development server from the VM to the host machine, allowing mobile devices on the local network to connect.

### Architecture

```
┌─────────────────────┐         SSH Tunnel          ┌─────────────────────┐
│   MOBILE DEVICE     │ ──────────────────────────► │   HOST MACHINE      │
│  (192.168.0.x)      │      exp://192.168.0.130    │  (192.168.0.130)    │
│                     │           :8081              │                     │
│                     │                              │   Port 8081 ────────┼──┐
└─────────────────────┘                              └─────────────────────┘  │
                                                                              │
                                                     ┌─────────────────────┐  │
                                                     │   VM (gcswebserver) │  │
                                                     │  (172.16.194.131)   │◄─┘
                                                     │                     │
                                                     │   Expo Dev Server   │
                                                     │   (localhost:8081)  │
                                                     └─────────────────────┘
```

### Configuration

| Component | Details |
|-----------|---------|
| Service | `expo-tunnel.service` |
| SSH Key | `~/.ssh/vm_expo` |
| Host Port | `0.0.0.0:8081` |
| VM Target | `localhost:8081` |
| Auto-reconnect | `autossh` with 30s keepalive |

### Service File

Location: `/etc/systemd/system/expo-tunnel.service`

```ini
[Unit]
Description=Expo SSH Tunnel to VM
After=network.target

[Service]
User=abhinavguru
ExecStart=/usr/bin/autossh -M 0 -N -g -L 0.0.0.0:8081:localhost:8081 -i /home/abhinavguru/.ssh/vm_expo -o "ServerAliveInterval=30" -o "ServerAliveCountMax=3" -o "StrictHostKeyChecking=accept-new" gcswebserver@172.16.194.131
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Commands

```bash
# Check tunnel status
sudo systemctl status expo-tunnel

# Start/Stop/Restart
sudo systemctl start expo-tunnel
sudo systemctl stop expo-tunnel
sudo systemctl restart expo-tunnel

# View logs
journalctl -u expo-tunnel -f

# Verify port is listening
ss -tlnp | grep 8081
```

### Mobile Connection

Connect your mobile device to: `exp://192.168.0.130:8081`
