#!/bin/bash
# Sync Primary Backup to Secondary Location (External Drive)
# This script mirrors /backup/ to an external drive for redundancy

set -euo pipefail

# Configuration
PRIMARY_DIR="/backup"
SECONDARY_BASE="/media/abhinavguru/BACKUPS"
SECONDARY_DIR="$SECONDARY_BASE/GuruColdStorage-Backup"
LOG_FILE="/backup/logs/secondary-sync.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Starting Secondary Location Sync ==="

# Check if external drive is mounted
if [ ! -d "$SECONDARY_BASE" ]; then
    log "⚠ Secondary backup location not mounted ($SECONDARY_BASE)"
    log "  Skipping secondary sync - primary backup is still safe"
    log "=== Secondary Sync Skipped ==="
    exit 0
fi

# Ensure secondary directory exists
mkdir -p "$SECONDARY_DIR"

log "Syncing from: $PRIMARY_DIR"
log "Syncing to: $SECONDARY_DIR"

# Sync with rsync
if rsync -av --delete \
    --stats \
    "$PRIMARY_DIR/" \
    "$SECONDARY_DIR/" 2>&1 | tee -a "$LOG_FILE"; then

    log "✓ Secondary sync complete"

    # Get directory size
    SIZE=$(du -sh "$SECONDARY_DIR" | cut -f1)
    log "  Total size: $SIZE"

    log "=== Secondary Location Sync Complete ==="
    exit 0
else
    log "✗ ERROR: Secondary sync failed!"
    exit 1
fi
