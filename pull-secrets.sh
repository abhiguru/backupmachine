#!/bin/bash
# Pull Encrypted Secrets from Primary Server
# This script syncs GPG-encrypted .env files

set -euo pipefail

# Configuration
PRIMARY_SERVER="primary-server"
SOURCE_PATH="/home/gcswebserver/ws/GuruColdStorageSupabase/secrets_backup/"
BACKUP_DIR="/backup/secrets"
LOG_FILE="/backup/logs/secrets-pull.log"
RETENTION_DAYS=7

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Starting Encrypted Secrets Sync ==="

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Sync encrypted files from primary server
log "Syncing from: $PRIMARY_SERVER:$SOURCE_PATH"
log "Syncing to: $BACKUP_DIR"

if rsync -avz \
    --include="*.gpg" \
    --exclude="*" \
    --stats \
    --log-file="$LOG_FILE" \
    "${PRIMARY_SERVER}:${SOURCE_PATH}" \
    "$BACKUP_DIR/" 2>&1 | tee -a "$LOG_FILE"; then

    log "✓ Secrets sync complete"

    # Count encrypted files
    FILE_COUNT=$(find "$BACKUP_DIR" -name "*.gpg" | wc -l)
    log "  Encrypted files: $FILE_COUNT"

    # Cleanup old encrypted backups
    log "Cleaning up secrets older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -name ".env.*.gpg" -mtime +$RETENTION_DAYS -delete

    log "=== Encrypted Secrets Sync Complete ==="
    exit 0
else
    log "✗ ERROR: Secrets sync failed!"
    exit 1
fi
