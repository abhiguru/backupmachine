#!/bin/bash
# Pull Source Code Backup from Primary Server
# Uses rsync to sync all projects, then creates timestamped tar.gz archives

set -euo pipefail

# Configuration
PRIMARY_SERVER="primary-server"
BACKUP_DIR="/backup/source"
STAGING_BASE="/backup/source-staging"
LOG_FILE="/backup/logs/source-pull.log"
RETENTION_DAYS=7

# Source paths to backup
declare -A SOURCES=(
    ["supabase"]="/home/gcswebserver/ws/GuruColdStorageSupabase"
    ["react-web"]="/home/gcswebserver/ws/GuruColdStorageReactWebSupabase"
    ["react-native"]="/home/gcswebserver/ws/GCSReactNative"
)

# Timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Starting Source Code Backup Pull ==="

# Ensure directories exist
mkdir -p "$BACKUP_DIR"

SYNC_SUCCESS=true

# Sync each source
for PROJECT in "${!SOURCES[@]}"; do
    SOURCE_PATH="${SOURCES[$PROJECT]}"
    STAGING_DIR="${STAGING_BASE}/${PROJECT}"
    BACKUP_FILE="${BACKUP_DIR}/${PROJECT}_backup_${TIMESTAMP}.tar.gz"

    mkdir -p "$STAGING_DIR"

    log ">>> Syncing: $PROJECT"
    log "    From: $SOURCE_PATH"

    if rsync -az --delete \
        --exclude='node_modules' \
        --exclude='.next' \
        --exclude='dist' \
        --exclude='build' \
        --exclude='.git' \
        --exclude='*.log' \
        --exclude='docker/volumes' \
        --exclude='android/.gradle' \
        --exclude='android/build' \
        --exclude='ios/Pods' \
        --exclude='.expo' \
        "${PRIMARY_SERVER}:${SOURCE_PATH}/" \
        "$STAGING_DIR/" 2>&1 | tee -a "$LOG_FILE"; then

        log "✓ $PROJECT sync successful"

        # Create tar.gz archive
        log "  Creating archive..."
        if tar czf "$BACKUP_FILE" -C "$STAGING_DIR" . 2>> "$LOG_FILE"; then
            SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            log "✓ $PROJECT archive: $SIZE"

            # Verify archive
            if ! gzip -t "$BACKUP_FILE" 2>/dev/null; then
                log "✗ ERROR: $PROJECT archive is corrupted"
                rm -f "$BACKUP_FILE"
                SYNC_SUCCESS=false
            fi
        else
            log "✗ ERROR: Failed to create $PROJECT archive"
            SYNC_SUCCESS=false
        fi
    else
        log "✗ ERROR: $PROJECT sync failed!"
        SYNC_SUCCESS=false
    fi
done

# Cleanup old backups for all projects
log "Cleaning up backups older than $RETENTION_DAYS days..."
for PROJECT in "${!SOURCES[@]}"; do
    find "$BACKUP_DIR" -name "${PROJECT}_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete
done
REMAINING=$(find "$BACKUP_DIR" -name "*_backup_*.tar.gz" | wc -l)
log "✓ Retention: $REMAINING total backups remaining"

if [ "$SYNC_SUCCESS" = true ]; then
    log "=== Source Code Backup Complete ==="
    exit 0
else
    log "=== Source Code Backup Complete (with errors) ==="
    exit 1
fi
