#!/bin/bash
# Pull File Storage from Primary Server
# This script syncs user-uploaded files (GRN images, documents)

set -euo pipefail

# Configuration
PRIMARY_SERVER="primary-server"
SOURCE_PATH="/home/gcswebserver/ws/GuruColdStorageSupabase/supabase/docker/volumes/storage/"
BACKUP_DIR="/backup/storage"
LOG_FILE="/backup/logs/storage-pull.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Starting File Storage Sync ==="

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Sync files from primary server
log "Syncing from: $PRIMARY_SERVER:$SOURCE_PATH"
log "Syncing to: $BACKUP_DIR"

if rsync -avz --delete \
    --stats \
    --log-file="$LOG_FILE" \
    "${PRIMARY_SERVER}:${SOURCE_PATH}" \
    "$BACKUP_DIR/" 2>&1 | tee -a "$LOG_FILE"; then

    log "✓ File storage sync complete"

    # Get directory size
    SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
    log "  Total size: $SIZE"

    # Count files
    FILE_COUNT=$(find "$BACKUP_DIR" -type f | wc -l)
    log "  Total files: $FILE_COUNT"

    log "=== File Storage Sync Complete ==="
    exit 0
else
    log "✗ ERROR: File storage sync failed!"
    exit 1
fi
