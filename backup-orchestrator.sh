#!/bin/bash
# Master Backup Orchestrator
# Runs all backup scripts in sequence

set -euo pipefail

SCRIPT_DIR="$HOME/backup-scripts"
LOG_FILE="/backup/logs/orchestrator.log"
LOCK_FILE="/tmp/backup-orchestrator.lock"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Acquire lock to prevent concurrent runs
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "✗ ERROR: Another backup is already running (lock file: $LOCK_FILE)"
    exit 1
fi

log "========================================="
log "=== BACKUP ORCHESTRATOR STARTED ==="
log "========================================="

# Track success/failure
SUCCESS_COUNT=0
FAIL_COUNT=0

# Run database backup
log ">>> Running: Database Backup"
if "$SCRIPT_DIR/pull-database.sh"; then
    log "✓ Database backup: SUCCESS"
    ((SUCCESS_COUNT++)) || true
else
    log "✗ Database backup: FAILED"
    ((FAIL_COUNT++)) || true
fi

# Run storage sync
log ">>> Running: File Storage Sync"
if "$SCRIPT_DIR/pull-storage.sh"; then
    log "✓ Storage sync: SUCCESS"
    ((SUCCESS_COUNT++)) || true
else
    log "✗ Storage sync: FAILED"
    ((FAIL_COUNT++)) || true
fi

# Run secrets sync
log ">>> Running: Encrypted Secrets Sync"
if "$SCRIPT_DIR/pull-secrets.sh"; then
    log "✓ Secrets sync: SUCCESS"
    ((SUCCESS_COUNT++)) || true
else
    log "✗ Secrets sync: FAILED"
    ((FAIL_COUNT++)) || true
fi

# Summary
log "========================================="
log "=== BACKUP ORCHESTRATOR SUMMARY ==="
log "  Successful: $SUCCESS_COUNT"
log "  Failed: $FAIL_COUNT"
if [ $FAIL_COUNT -eq 0 ]; then
    log "  Status: ✓ ALL BACKUPS SUCCESSFUL"
    log "========================================="
    exit 0
else
    log "  Status: ✗ SOME BACKUPS FAILED"
    log "========================================="
    exit 1
fi
