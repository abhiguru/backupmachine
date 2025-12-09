#!/bin/bash
# Pull Database Backup from Primary Server
# This script pulls a PostgreSQL dump from the primary server

set -euo pipefail

# Configuration
PRIMARY_SERVER="primary-server"
BACKUP_DIR="/backup/database"
LOG_FILE="/backup/logs/database-pull.log"
RETENTION_DAYS=28

# Timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/supabase_backup_${TIMESTAMP}.sql"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Starting Database Backup Pull ==="

# Pull database dump from primary server
log "Connecting to primary server: $PRIMARY_SERVER"
if ssh "$PRIMARY_SERVER" "/home/gcswebserver/ws/GuruColdStorageSupabase/backup-scripts/restricted-db-backup.sh" > "$BACKUP_FILE" 2>> "$LOG_FILE"; then
    log "✓ Database dump successful"

    # Get file size
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "  Backup size: $SIZE"

    # Verify file is not empty
    if [ ! -s "$BACKUP_FILE" ]; then
        log "✗ ERROR: Backup file is empty!"
        exit 1
    fi

    # Count SQL dump markers
    if grep -q "PostgreSQL database dump complete" "$BACKUP_FILE"; then
        log "✓ Backup integrity check passed"
    else
        log "✗ ERROR: Backup incomplete (missing completion marker)"
        rm -f "$BACKUP_FILE"
        exit 1
    fi

    # Compress backup
    log "Compressing backup..."
    gzip -9 "$BACKUP_FILE"
    COMPRESSED_SIZE=$(du -h "${BACKUP_FILE}.gz" | cut -f1)
    log "✓ Compressed size: $COMPRESSED_SIZE"

    # Cleanup old backups
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -name "supabase_backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete
    REMAINING=$(find "$BACKUP_DIR" -name "supabase_backup_*.sql.gz" | wc -l)
    log "✓ Retention: $REMAINING backups remaining"

    log "=== Database Backup Complete ==="
    exit 0
else
    log "✗ ERROR: Database dump failed!"
    rm -f "$BACKUP_FILE"
    exit 1
fi
