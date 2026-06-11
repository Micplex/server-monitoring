#!/usr/bin/env bash
# =============================================================
# cleanup_data.sh — Data Directory Retention Policy
# =============================================================
# WHY: TSV metric files accumulate ~50KB/day per server.
#      At 30 servers, that's 1.5MB/day, 550MB/year.
#      This script enforces a data retention policy, deleting
#      metric files older than DATA_RETENTION_DAYS.
# =============================================================

SCRIPT_NAME="cleanup_data.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"

DATA_RETENTION_DAYS="${DATA_RETENTION_DAYS:-90}"

log_start
log_info "Cleaning data older than ${DATA_RETENTION_DAYS} days"

local before_size
before_size=$(du -sh "${DATA_DIR}" 2>/dev/null | awk '{print $1}')

# Delete TSV metric files older than retention period
find "${DATA_DIR}/metrics" -name "*.tsv" -mtime "+${DATA_RETENTION_DAYS}" -delete 2>/dev/null
find "${DATA_DIR}/alerts" -name "*.log" -mtime "+${DATA_RETENTION_DAYS}" -delete 2>/dev/null
find "${DATA_DIR}/reports" -name "daily_*.txt" -mtime "+${DATA_RETENTION_DAYS}" -delete 2>/dev/null

# Keep weekly reports longer (6 months)
find "${DATA_DIR}/reports" -name "weekly_*.txt" -mtime "+180" -delete 2>/dev/null

# Clean dedup state of very old entries
local dedup_file="${DATA_DIR}/alerts/dedup_state.tsv"
if [[ -f "$dedup_file" ]]; then
    local cutoff
    cutoff="$(date -d '24 hours ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '1970-01-01')"
    local tmp
    tmp=$(mktemp)
    awk -F'\t' -v cutoff="$cutoff" '$1 >= cutoff' "$dedup_file" > "$tmp"
    mv "$tmp" "$dedup_file"
fi

local after_size
after_size=$(du -sh "${DATA_DIR}" 2>/dev/null | awk '{print $1}')
log_info "Data cleanup complete. Before: ${before_size} → After: ${after_size}"
log_end 0
