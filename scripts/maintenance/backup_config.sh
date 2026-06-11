#!/usr/bin/env bash
# =============================================================
# backup_config.sh — Configuration Backup
# =============================================================
# WHY: Config files contain months of tuned thresholds and
#      notification settings. Losing them to accidental edits
#      or server failure is painful. This creates timestamped
#      backups before any configuration change.
# =============================================================

SCRIPT_NAME="backup_config.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"

BACKUP_DIR="${DATA_DIR}/backups"
BACKUP_KEEP="${BACKUP_KEEP_COUNT:-10}"

log_start
mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
BACKUP_FILE="${BACKUP_DIR}/config_backup_${TIMESTAMP}.tar.gz"

# Archive config directory (excluding .env with secrets)
tar czf "$BACKUP_FILE" \
    --exclude="${PROJECT_ROOT}/.env" \
    -C "${PROJECT_ROOT}" \
    config/ alerts/ \
    2>/dev/null

if [[ $? -eq 0 ]]; then
    local size
    size=$(du -sh "$BACKUP_FILE" | awk '{print $1}')
    log_info "Config backup created: ${BACKUP_FILE} (${size})"
else
    log_error "Config backup FAILED"
    exit 1
fi

# Keep only the N most recent backups
local backup_count
backup_count=$(ls -1 "${BACKUP_DIR}/config_backup_"*.tar.gz 2>/dev/null | wc -l)
if (( backup_count > BACKUP_KEEP )); then
    ls -1t "${BACKUP_DIR}/config_backup_"*.tar.gz | tail -n "+$((BACKUP_KEEP + 1))" | xargs rm -f
    log_info "Pruned old backups (keeping ${BACKUP_KEEP} most recent)"
fi

log_end 0
