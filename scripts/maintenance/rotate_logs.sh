#!/usr/bin/env bash
# =============================================================
# rotate_logs.sh — Log Rotation & Compression
# =============================================================
# WHY: Monitoring logs grow continuously. Without rotation, the
#      monitoring system eventually fills the disk it's watching.
#      This script compresses old logs and deletes those beyond
#      the retention period — keeping disk usage bounded.
#
# STRATEGY:
#   - Logs older than 1 day → gzip compressed
#   - Logs older than LOG_RETENTION_DAYS → deleted
#   - Monthly archives kept for LOG_ARCHIVE_MONTHS months
# =============================================================

SCRIPT_NAME="rotate_logs.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"

LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
LOG_ARCHIVE_MONTHS="${LOG_ARCHIVE_MONTHS:-3}"

log_start
log_info "Starting log rotation (retention=${LOG_RETENTION_DAYS}d, archive=${LOG_ARCHIVE_MONTHS}m)"

# Compress logs older than 1 day that aren't already compressed
find "$LOG_DIR" -name "*.log" -mtime +1 ! -name "*.gz" 2>/dev/null | while read -r logfile; do
    gzip -9 "$logfile" && log_info "Compressed: $(basename "$logfile")"
done

# Delete compressed logs older than retention period
local deleted=0
find "$LOG_DIR" -name "*.gz" -mtime "+${LOG_RETENTION_DAYS}" 2>/dev/null | while read -r old_log; do
    rm -f "$old_log"
    log_info "Deleted old log: $(basename "$old_log")"
    ((deleted++))
done

# Signal logrotate if config exists
if [[ -f "${LOG_DIR}/.logrotate" ]]; then
    logrotate "${LOG_DIR}/.logrotate" 2>/dev/null && log_info "logrotate config applied"
fi

log_info "Log rotation complete"
log_end 0
