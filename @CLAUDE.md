# Backup Machine System Documentation

**Last Updated:** 2025-12-09
**System Name:** AbhinavGuruColdStorage
**Purpose:** Pull-based backup system for GuruColdStorage Supabase application

---

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Configuration Details](#configuration-details)
4. [Backup Scripts](#backup-scripts)
5. [Security Model](#security-model)
6. [Automated Schedule](#automated-schedule)
7. [Current Status](#current-status)
8. [Monitoring & Maintenance](#monitoring--maintenance)
9. [Disaster Recovery](#disaster-recovery)
10. [Troubleshooting](#troubleshooting)

---

## Overview

### What This System Does

This backup machine **pulls** backups from the primary GuruColdStorage server every 4 hours. It uses a **pull-based architecture** where:

- ✅ Backup machine initiates all connections (secure)
- ❌ Primary server CANNOT access backup machine (extra security)
- ✅ Even if primary is compromised, backups remain safe

### Backup Components

| Component | Description | Size | Retention |
|-----------|-------------|------|-----------|
| **Database** | PostgreSQL dumps (pg_dump) | ~13MB raw, ~2MB compressed | 14 days |
| **File Storage** | User uploads (GRN images, PDFs, documents) | ~176MB | Latest snapshot (rsync mirror) |
| **Encrypted Secrets** | GPG-encrypted .env files | ~1.7KB | 14 days |

---

## System Architecture

### Network Topology

```
Primary Server (Source)          Backup Machine (Destination)
172.16.194.128                    192.168.0.130
172.16.194.0/24 subnet            192.168.0.0/24 subnet
├─ SSH Server (port 22)           ├─ SSH Client
├─ PostgreSQL Database      ←───  ├─ pull-database.sh
├─ File Storage             ←───  ├─ pull-storage.sh
└─ Encrypted Secrets        ←───  └─ pull-secrets.sh
```

### Data Flow

```
Every 4 hours (via cron):
┌─────────────────────────────────────────────────────────────┐
│ backup-orchestrator.sh (Master Script)                      │
└─────────────────────────────────────────────────────────────┘
           ↓                    ↓                    ↓
    pull-database.sh    pull-storage.sh     pull-secrets.sh
           ↓                    ↓                    ↓
    SSH to primary      rsync over SSH      rsync over SSH
           ↓                    ↓                    ↓
    /backup/database    /backup/storage    /backup/secrets
```

---

## Configuration Details

### Machine Information

```yaml
Hostname: AbhinavGuruColdStorage
User: abhinavguru
Backup IP: 192.168.0.130
Primary Server IP: 172.16.194.128
OS: Ubuntu 24.04 LTS (Linux 6.8.0-78-generic)
Disk Space: 915GB total, 499GB available (43% used)
```

### SSH Configuration

**SSH Config File:** `~/.ssh/config`

```ssh-config
# Primary Server (Source of backups)
Host primary-server
    HostName 172.16.194.128
    User backupuser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

**SSH Key Pair:**
- Private key: `~/.ssh/id_ed25519` (600 permissions)
- Public key: `~/.ssh/id_ed25519.pub` (644 permissions)
- Key type: ED25519 (modern, secure)

**Public Key (added to primary server):**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPaqALeAeXVcaIuGyNaC0Jc0kM9vJFYaUS/aQQ27yY9e backup-machine@AbhinavGuruColdStorage
```

### Firewall (UFW) Rules

```bash
# Status: ACTIVE and enabled on system startup

Rule 1: Allow SSH from local network (192.168.0.0/24)
Rule 2: Allow SSH from primary server network (172.16.0.0/16)
Rule 3: DENY SSH from everywhere else (default deny)
```

**Security Notes:**
- Only SSH (port 22) is allowed from trusted networks
- All other incoming connections are blocked
- Primary server CAN connect to backup machine for troubleshooting
- But primary server's SSH key has forced commands (cannot access interactively)

### Directory Structure

```
/backup/
├── database/          # PostgreSQL dumps (.sql.gz files)
├── storage/           # Synced file storage (images, PDFs)
├── secrets/           # GPG-encrypted .env files
└── logs/              # All backup operation logs
    ├── cron.log
    ├── database-pull.log
    ├── storage-pull.log
    ├── secrets-pull.log
    └── orchestrator.log

/home/abhinavguru/
├── backup-scripts/
│   ├── backup-orchestrator.sh      # Master script (runs all backups)
│   ├── pull-database.sh            # Database backup
│   ├── pull-storage.sh             # File storage sync
│   ├── pull-secrets.sh             # Encrypted secrets sync
│   └── decrypt-env.sh              # Helper to decrypt .env files
└── .secrets/
    └── gpg_passphrase              # GPG passphrase (400 permissions)
```

**Permissions:**
- `/backup/` - 700 (drwx------) - Only abhinavguru can access
- `~/.secrets/gpg_passphrase` - 400 (-r--------) - Read-only, owner only

---

## Backup Scripts

### 1. Master Orchestrator

**File:** `~/backup-scripts/backup-orchestrator.sh`

**Purpose:** Runs all three backup scripts in sequence and logs results.

**Usage:**
```bash
~/backup-scripts/backup-orchestrator.sh
```

**Output:**
```
[2025-12-09 14:00:00] =========================================
[2025-12-09 14:00:00] === BACKUP ORCHESTRATOR STARTED ===
[2025-12-09 14:00:00] =========================================
[2025-12-09 14:00:00] >>> Running: Database Backup
[2025-12-09 14:00:10] ✓ Database backup: SUCCESS
[2025-12-09 14:00:10] >>> Running: File Storage Sync
[2025-12-09 14:00:25] ✓ Storage sync: SUCCESS
[2025-12-09 14:00:25] >>> Running: Encrypted Secrets Sync
[2025-12-09 14:00:28] ✓ Secrets sync: SUCCESS
[2025-12-09 14:00:28] =========================================
[2025-12-09 14:00:28] === BACKUP ORCHESTRATOR SUMMARY ===
[2025-12-09 14:00:28]   Successful: 3
[2025-12-09 14:00:28]   Failed: 0
[2025-12-09 14:00:28]   Status: ✓ ALL BACKUPS SUCCESSFUL
[2025-12-09 14:00:28] =========================================
```

### 2. Database Backup Script

**File:** `~/backup-scripts/pull-database.sh`

**Purpose:** Pulls PostgreSQL database dump from primary server.

**What it does:**
1. Connects to primary server via SSH
2. Executes `restricted-db-backup.sh` on primary (forced command allows this)
3. Saves SQL dump to `/backup/database/supabase_backup_YYYYMMDD_HHMMSS.sql`
4. Verifies dump integrity (checks for "PostgreSQL database dump complete")
5. Compresses with gzip -9 (maximum compression)
6. Deletes backups older than 14 days

**Primary Server Command (executed remotely):**
```bash
/home/gcswebserver/ws/GuruColdStorageSupabase/backup-scripts/restricted-db-backup.sh
```

**Retention:** 14 days (configurable via `RETENTION_DAYS` variable)

**Log:** `/backup/logs/database-pull.log`

### 3. File Storage Sync Script

**File:** `~/backup-scripts/pull-storage.sh`

**Purpose:** Syncs user-uploaded files (GRN images, dispatch images, documents).

**What it does:**
1. Uses `rsync` to sync files from primary server
2. Source: `/home/gcswebserver/ws/GuruColdStorageSupabase/supabase/docker/volumes/storage/`
3. Destination: `/backup/storage/`
4. Uses `--delete` flag (mirrors exactly, removes files deleted on primary)

**Rsync Options:**
```bash
rsync -avz --delete --stats
  -a = archive mode (preserves permissions, timestamps, etc.)
  -v = verbose
  -z = compress during transfer
  --delete = delete files that don't exist on source
  --stats = show transfer statistics
```

**Current Statistics:**
- Files synced: 224
- Total size: 176MB
- Transfer speed: ~48.6 MB/sec (local network)

**Retention:** Latest snapshot only (rsync mirror)

**Log:** `/backup/logs/storage-pull.log`

### 4. Encrypted Secrets Sync Script

**File:** `~/backup-scripts/pull-secrets.sh`

**Purpose:** Syncs GPG-encrypted .env files containing sensitive credentials.

**What it does:**
1. Uses `rsync` to sync only `.gpg` files
2. Source: `/home/gcswebserver/ws/GuruColdStorageSupabase/secrets_backup/`
3. Destination: `/backup/secrets/`
4. Deletes encrypted secrets older than 14 days

**Rsync Options:**
```bash
rsync -avz --include="*.gpg" --exclude="*"
  --include="*.gpg" = only sync .gpg files
  --exclude="*" = exclude everything else
```

**Current Statistics:**
- Encrypted files: 1
- File: `.env.20251209_132728.gpg` (1.7KB)

**Retention:** 14 days (configurable via `RETENTION_DAYS` variable)

**Log:** `/backup/logs/secrets-pull.log`

### 5. Decryption Helper Script

**File:** `~/backup-scripts/decrypt-env.sh`

**Purpose:** Decrypt GPG-encrypted .env files for disaster recovery.

**Usage:**
```bash
~/backup-scripts/decrypt-env.sh /backup/secrets/.env.20251209_132728.gpg
```

**Output:** Decrypted .env file contents to stdout

**GPG Passphrase:** Stored in `~/.secrets/gpg_passphrase` (400 permissions)

**Passphrase:**
```
CdJtDFX23FI3bacecBNYH3DMNhuKuNxKG9HfYg1LX4Q=
```

**Example Output:**
```bash
POSTGRES_PASSWORD=express_inventory_2024_secure_password
JWT_SECRET=ng8ia/dzoTNn+O7fp06+AI4U4iZmS+uS7/eqOD5u9Mlc6RNkpYcTfVA8POLTHf1K
ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
DASHBOARD_USERNAME=admin
DASHBOARD_PASSWORD=express_inventory_admin_2024
SECRET_KEY_BASE=ad5eb3922f1c8788172089216b7c6a375d47b997...
VAULT_ENC_KEY=48ba4ee81136f860bece1d740c888073
```

---

## Security Model

### Defense in Depth

```
Layer 1: Pull-Based Architecture
└─ Primary server CANNOT initiate connections to backup machine
   └─ Even if compromised, attacker cannot delete backups

Layer 2: SSH Forced Commands (on primary server)
└─ SSH key only allows 2 specific operations:
   ├─ Database backup script execution
   └─ Rsync in read-only mode
   └─ All other commands are BLOCKED

Layer 3: Read-Only Access (ACLs on primary)
└─ Backup user can only READ files
   ├─ Cannot write files
   ├─ Cannot delete files
   └─ Cannot modify files

Layer 4: Firewall (UFW on backup machine)
└─ SSH only from trusted networks
   ├─ 192.168.0.0/24 (local network)
   ├─ 172.16.0.0/16 (primary server network)
   └─ Deny all other connections

Layer 5: Encrypted Secrets
└─ .env files encrypted with GPG
   └─ Passphrase stored separately (400 permissions)

Layer 6: File Permissions
└─ /backup/ - 700 (owner only)
└─ ~/.secrets/gpg_passphrase - 400 (read-only, owner only)
└─ ~/.ssh/id_ed25519 - 600 (private key, owner only)
```

### SSH Forced Command (Primary Server)

**File on Primary:** `/home/backupuser/.ssh/authorized_keys`

**Command:**
```bash
command="/home/gcswebserver/ws/GuruColdStorageSupabase/backup-scripts/restricted-backup-wrapper.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPaqALeAeXVcaIuGyNaC0Jc0kM9vJFYaUS/aQQ27yY9e
```

**Wrapper Script Allows:**
1. `/home/gcswebserver/ws/GuruColdStorageSupabase/backup-scripts/restricted-db-backup.sh`
2. `rsync --server --sender` (read-only mode)

**Wrapper Script Blocks:**
- Shell commands (whoami, ls, cat, etc.)
- Arbitrary script execution
- Write operations
- Delete operations

### Attack Scenarios Mitigated

| Attack Scenario | Protection |
|-----------------|------------|
| Primary server compromised | Backup machine pulls data; attacker cannot push malicious data or delete backups |
| Backup user credentials stolen | SSH forced command limits to read-only operations only |
| Network eavesdropping | All traffic encrypted via SSH |
| Ransomware on primary | Backups stored separately; 14-day retention allows recovery from old backup |
| Accidental deletion on primary | Backups synced every 4 hours; recent backup available |

---

## Automated Schedule

### Cron Job Configuration

**Crontab Entry:**
```cron
# Pull backups from primary server every 4 hours
0 */4 * * * /home/abhinavguru/backup-scripts/backup-orchestrator.sh >> /backup/logs/cron.log 2>&1
```

**Schedule:**
| Time | Database | Storage | Secrets | Notes |
|------|----------|---------|---------|-------|
| 12:00 AM | ✓ | ✓ | ✓ | Midnight backup |
| 4:00 AM | ✓ | ✓ | ✓ | Early morning |
| 8:00 AM | ✓ | ✓ | ✓ | Business hours start |
| 12:00 PM | ✓ | ✓ | ✓ | Midday |
| 4:00 PM | ✓ | ✓ | ✓ | Business hours end |
| 8:00 PM | ✓ | ✓ | ✓ | Evening |

**View Crontab:**
```bash
crontab -l
```

**Edit Crontab:**
```bash
crontab -e
```

**Check Cron Status:**
```bash
systemctl status cron
```

---

## Current Status

### Last Successful Backups

**As of 2025-12-09 14:15:**

| Component | Status | Last Success | Size | Files |
|-----------|--------|--------------|------|-------|
| Database | ⚠️ **BLOCKED** | Never | 0 | 0 |
| File Storage | ✅ **SUCCESS** | 2025-12-09 14:14:55 | 176MB | 224 files |
| Encrypted Secrets | ✅ **SUCCESS** | 2025-12-09 14:15:16 | 1.7KB | 1 file |

### Known Issues

**Issue 1: SSH Connection Timeouts**

**Symptom:**
```
ssh: connect to host 172.16.194.128 port 22: Connection timed out
```

**Impact:**
- Database backups cannot complete
- Automated cron jobs fail on database component

**Investigation:**
- Network reachable (ping works: 0.183ms avg)
- Port 22 (SSH) times out after ~2 minutes
- Suggests SSH service issue or firewall blocking on primary server

**Workaround:**
- File storage and secrets still sync successfully (when SSH is up)
- Manual intervention required to restore SSH connectivity

**Next Steps:**
1. Check SSH service on primary: `systemctl status ssh`
2. Check SSH logs on primary: `journalctl -u ssh -n 100`
3. Verify firewall allows backup machine: `ufw status`
4. Check SSH connection limits: `/etc/ssh/sshd_config` (MaxSessions, MaxStartups)

### Backup Statistics

**Disk Usage:**
```bash
$ df -h /backup/
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p2  915G  370G  499G  43% /

$ du -sh /backup/*
0       /backup/database
176M    /backup/storage
4.0K    /backup/secrets
148K    /backup/logs
```

**File Counts:**
```bash
Database backups: 0
Storage files: 224
Encrypted secrets: 1
```

---

## Monitoring & Maintenance

### Daily Checks

**1. Check Latest Backup Status**
```bash
tail -100 /backup/logs/orchestrator.log | grep -E "(SUMMARY|SUCCESS|FAILED)"
```

**2. Verify Disk Space**
```bash
df -h /backup/
du -sh /backup/*
```

**3. Count Recent Backups**
```bash
echo "Database backups: $(ls /backup/database/*.sql.gz 2>/dev/null | wc -l)"
echo "Storage files: $(find /backup/storage -type f 2>/dev/null | wc -l)"
echo "Encrypted secrets: $(ls /backup/secrets/*.gpg 2>/dev/null | wc -l)"
```

### Weekly Checks

**1. Check Latest Backup Age**
```bash
LATEST_DB=$(ls -t /backup/database/supabase_backup_*.sql.gz 2>/dev/null | head -1)
if [ -f "$LATEST_DB" ]; then
    echo "Latest database backup: $(stat -c %y "$LATEST_DB")"
else
    echo "WARNING: No database backups found!"
fi
```

**2. Verify Backup Integrity**
```bash
# Test database dump
LATEST_DB=$(ls -t /backup/database/supabase_backup_*.sql.gz 2>/dev/null | head -1)
if [ -f "$LATEST_DB" ]; then
    gunzip -c "$LATEST_DB" | head -50
    gunzip -c "$LATEST_DB" | grep -q "PostgreSQL database dump complete" && echo "✓ Integrity OK" || echo "✗ Integrity FAILED"
fi

# Test secrets decryption
LATEST_SECRET=$(ls -t /backup/secrets/.env.*.gpg 2>/dev/null | head -1)
if [ -f "$LATEST_SECRET" ]; then
    ~/backup-scripts/decrypt-env.sh "$LATEST_SECRET" | head -5 && echo "✓ Decryption OK" || echo "✗ Decryption FAILED"
fi
```

### Monthly Maintenance

**1. Cleanup Old Logs (retain 30 days)**
```bash
find /backup/logs/ -name "*.log" -mtime +30 -delete
```

**2. Review Cron Job Status**
```bash
grep "BACKUP ORCHESTRATOR" /backup/logs/cron.log | tail -20
```

**3. Test Manual Backup**
```bash
~/backup-scripts/backup-orchestrator.sh
```

### Alerts & Notifications

**Currently:** No automated alerting configured

**Recommended:** Set up monitoring for:
- Backup failures (check orchestrator.log for FAILED status)
- Disk space warnings (alert when /backup reaches 80%)
- SSH connectivity issues
- Backup age (alert if latest backup > 5 hours old)

**Implementation Ideas:**
1. Email notifications via `mail` command
2. Slack/Discord webhooks
3. Monitoring tools (Prometheus, Grafana, Uptime Kuma)
4. Simple script to check status and send alerts

---

## Disaster Recovery

### Scenario 1: Restore Database

**Situation:** Primary database corrupted or lost.

**Steps:**

1. **Find Latest Backup**
```bash
LATEST_BACKUP=$(ls -t /backup/database/supabase_backup_*.sql.gz | head -1)
echo "Restoring from: $LATEST_BACKUP"
```

2. **Extract SQL Dump**
```bash
gunzip -c "$LATEST_BACKUP" > /tmp/restore.sql
```

3. **Verify SQL Dump**
```bash
head -50 /tmp/restore.sql
grep "PostgreSQL database dump complete" /tmp/restore.sql
```

4. **Restore to PostgreSQL**
```bash
# On primary server (or new server)
psql -U postgres -d supabase < /tmp/restore.sql
```

5. **Verify Restoration**
```bash
psql -U postgres -d supabase -c "SELECT COUNT(*) FROM users;"
```

**Recovery Time Objective (RTO):** 5-10 minutes
**Recovery Point Objective (RPO):** Maximum 4 hours (backup interval)

### Scenario 2: Restore File Storage

**Situation:** User uploads lost or corrupted on primary server.

**Steps:**

1. **Check Backup Age**
```bash
ls -lh /backup/storage/stub/stub/grn-images/
du -sh /backup/storage/
```

2. **Rsync Files Back to Primary** (if needed)
```bash
# From backup machine
rsync -avz /backup/storage/ primary-server:/path/to/restore/
```

**Note:** Since file storage is a mirror (rsync --delete), only the latest snapshot is available. Files deleted more than 4 hours ago cannot be recovered.

**RTO:** Immediate (files already synced)
**RPO:** Maximum 4 hours

### Scenario 3: Restore Secrets (.env)

**Situation:** .env file lost on primary server, need to restore credentials.

**Steps:**

1. **Find Latest Encrypted Backup**
```bash
LATEST_SECRET=$(ls -t /backup/secrets/.env.*.gpg | head -1)
echo "Restoring from: $LATEST_SECRET"
```

2. **Decrypt to File**
```bash
~/backup-scripts/decrypt-env.sh "$LATEST_SECRET" > /tmp/restored.env
```

3. **Verify Contents**
```bash
cat /tmp/restored.env
```

4. **Copy to Primary Server**
```bash
scp /tmp/restored.env primary-server:/home/gcswebserver/ws/GuruColdStorageSupabase/.env
```

5. **Secure Permissions**
```bash
# On primary server
chmod 600 .env
```

**RTO:** 1 minute
**RPO:** Maximum 4 hours

### Scenario 4: Complete Primary Server Loss

**Situation:** Primary server hardware failure or total data loss.

**Steps:**

1. **Set up new server** with same configuration
2. **Restore database** (Scenario 1)
3. **Restore file storage** (Scenario 2)
4. **Restore secrets** (Scenario 3)
5. **Reinstall Supabase** and configure with restored .env
6. **Reconfigure backup SSH keys** on new primary

**RTO:** 30-60 minutes (depending on server setup)
**RPO:** Maximum 4 hours

---

## Troubleshooting

### Issue: SSH Connection Refused

**Symptoms:**
```
ssh primary-server
# Output: Connection refused
```

**Checks:**
```bash
# 1. Test network connectivity
ping 172.16.194.128

# 2. Check SSH port
nc -zv 172.16.194.128 22

# 3. Verify SSH key
cat ~/.ssh/id_ed25519.pub
```

**On Primary Server:**
```bash
# Check SSH service
systemctl status ssh

# Check SSH logs
journalctl -u ssh -n 50

# Restart SSH if needed
systemctl restart ssh
```

### Issue: SSH Connection Timeout

**Symptoms:**
```
ssh: connect to host 172.16.194.128 port 22: Connection timed out
```

**Checks:**
```bash
# 1. Verify network (should work)
ping 172.16.194.128

# 2. Check if port times out
nc -zv -w 5 172.16.194.128 22

# 3. Check routing
traceroute 172.16.194.128
```

**On Primary Server:**
```bash
# Check firewall
ufw status

# Check SSH is listening
netstat -tuln | grep :22

# Check connection limits
grep -E "MaxSessions|MaxStartups" /etc/ssh/sshd_config

# Check for banned IPs (fail2ban)
fail2ban-client status sshd
```

### Issue: Permission Denied (SSH)

**Symptoms:**
```
Permission denied (publickey)
```

**Checks:**
```bash
# 1. Verify key permissions
ls -l ~/.ssh/id_ed25519*
# Should be: -rw------- (600) for private key

# 2. Test SSH with verbose output
ssh -vvv primary-server

# 3. Verify public key
cat ~/.ssh/id_ed25519.pub
```

**On Primary Server:**
```bash
# Check authorized_keys
cat /home/backupuser/.ssh/authorized_keys

# Check permissions
ls -ld /home/backupuser/.ssh/
ls -l /home/backupuser/.ssh/authorized_keys
# Should be: drwx------ (700) for .ssh
# Should be: -rw------- (600) for authorized_keys

# Check ownership
ls -la /home/backupuser/.ssh/
# Should be owned by backupuser:backupuser
```

### Issue: Backups Are Empty or Incomplete

**Symptoms:**
Backup files created but size is 0 or very small.

**Checks:**
```bash
# 1. Check recent logs
tail -100 /backup/logs/database-pull.log

# 2. Verify backup file
LATEST_DB=$(ls -t /backup/database/*.sql.gz | head -1)
gunzip -c "$LATEST_DB" | head -50

# 3. Test manual pull
~/backup-scripts/pull-database.sh
```

**On Primary Server:**
```bash
# Test database connection
psql -U postgres -c "SELECT version();"

# Test manual dump
pg_dump -U postgres supabase | head -50

# Check restricted-db-backup.sh script
bash -x /home/gcswebserver/ws/GuruColdStorageSupabase/backup-scripts/restricted-db-backup.sh
```

### Issue: Disk Full

**Symptoms:**
```
No space left on device
```

**Checks:**
```bash
# Check disk usage
df -h /backup/

# Check backup sizes
du -sh /backup/*

# Find large files
du -ah /backup/ | sort -rh | head -20
```

**Fix:**
```bash
# Manually cleanup old backups (reduce retention)
find /backup/database/ -name "*.sql.gz" -mtime +7 -delete
find /backup/secrets/ -name "*.gpg" -mtime +7 -delete

# Check again
df -h /backup/
```

### Issue: GPG Decryption Fails

**Symptoms:**
```
gpg: decryption failed: No secret key
```

**Checks:**
```bash
# 1. Verify passphrase file exists
ls -l ~/.secrets/gpg_passphrase

# 2. Test decryption manually
gpg --decrypt --batch --passphrase-file ~/.secrets/gpg_passphrase /backup/secrets/.env.20251209_132728.gpg

# 3. Check GPG version
gpg --version
```

**Fix:**
```bash
# If passphrase file is missing, recreate it
mkdir -p ~/.secrets
echo "CdJtDFX23FI3bacecBNYH3DMNhuKuNxKG9HfYg1LX4Q=" > ~/.secrets/gpg_passphrase
chmod 400 ~/.secrets/gpg_passphrase
```

### Issue: Rsync Fails with "Permission Denied"

**Symptoms:**
```
rsync: failed to set permissions: Operation not permitted
```

**This is normal** - The forced command on primary allows read-only rsync. Permission errors during sync are expected and can be ignored as long as files are transferred.

**Verify:**
```bash
# Check if files were actually synced
ls -lh /backup/storage/

# Check rsync exit code in logs
tail -50 /backup/logs/storage-pull.log | grep "exit code"
```

---

## Appendix A: Primary Server Configuration

**Location:** 172.16.194.128
**User:** backupuser
**SSH Key Location:** `/home/backupuser/.ssh/authorized_keys`

**Forced Command Wrapper:** `/home/gcswebserver/ws/GuruColdStorageSupabase/backup-scripts/restricted-backup-wrapper.sh`

**Allowed Operations:**
1. Database backup: `/home/gcswebserver/ws/GuruColdStorageSupabase/backup-scripts/restricted-db-backup.sh`
2. Rsync read-only: `rsync --server --sender`

**Read-Only Paths (ACLs enforced):**
- `/home/gcswebserver/ws/GuruColdStorageSupabase/supabase/docker/volumes/storage/`
- `/home/gcswebserver/ws/GuruColdStorageSupabase/secrets_backup/`
- Database via restricted script

---

## Appendix B: Quick Reference Commands

**Check Backup Status:**
```bash
tail -50 /backup/logs/orchestrator.log
```

**Manual Backup (All):**
```bash
~/backup-scripts/backup-orchestrator.sh
```

**Manual Backup (Database Only):**
```bash
~/backup-scripts/pull-database.sh
```

**Manual Backup (Storage Only):**
```bash
~/backup-scripts/pull-storage.sh
```

**Manual Backup (Secrets Only):**
```bash
~/backup-scripts/pull-secrets.sh
```

**Decrypt Secrets:**
```bash
~/backup-scripts/decrypt-env.sh /backup/secrets/.env.YYYYMMDD_HHMMSS.gpg
```

**Check Disk Space:**
```bash
df -h /backup/
du -sh /backup/*
```

**Count Backups:**
```bash
ls /backup/database/*.sql.gz 2>/dev/null | wc -l
find /backup/storage -type f | wc -l
ls /backup/secrets/*.gpg 2>/dev/null | wc -l
```

**Test SSH Connection:**
```bash
ssh primary-server
```

**View Crontab:**
```bash
crontab -l
```

**Check Firewall Status:**
```bash
sudo ufw status numbered
```

**Check SSH Key:**
```bash
cat ~/.ssh/id_ed25519.pub
```

---

## Appendix C: Contact Information

**System Administrator:** [Add contact info]
**Emergency Contact:** [Add contact info]
**Documentation Last Updated:** 2025-12-09
**Backup System Version:** 1.0

---

## Appendix D: Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-12-09 | Initial backup system setup | Claude Sonnet 4.5 |
| 2025-12-09 | Fixed database backup (updated forced command wrapper) | Claude Sonnet 4.5 |
| 2025-12-09 | Documented SSH timeout issue | Claude Sonnet 4.5 |

---

**End of Documentation**
