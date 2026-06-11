#!/usr/bin/env bash
# =============================================================
# weekly.sh — Weekly Trend Analysis Report
# =============================================================
# WHY: Daily reports show what happened. Weekly reports show
#      TRENDS — is disk usage growing week over week? Is the
#      server getting slower? These are the conversations that
#      lead to hardware upgrades and justify your monitoring fee.
# =============================================================

SCRIPT_NAME="weekly.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"

HOSTNAME="$(hostname -s 2>/dev/null || hostname)"
WEEK_END="${1:-$(date '+%Y-%m-%d')}"
REPORT_FILE="${DATA_DIR}/reports/weekly_${WEEK_END}.txt"

log_start
log_info "Generating weekly report ending ${WEEK_END}"

{
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              WEEKLY SYSTEM TREND REPORT                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
printf "  Host:       %s\n" "$HOSTNAME"
printf "  Week Ending:%s\n" "$WEEK_END"
printf "  Generated:  %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
echo ""

echo "── WEEK-OVER-WEEK HEALTH SCORES ─────────────────────────────"
local score_log="${DATA_DIR}/reports/health_scores.tsv"
if [[ -f "$score_log" ]]; then
    # Get last 7 days of scores with daily averages
    for i in 6 5 4 3 2 1 0; do
        local day
        day=$(date -d "${i} days ago" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
        local avg
        avg=$(awk -F'\t' -v d="$day" '$1 ~ d { sum+=$3; count++ } END { if(count>0) printf "%.0f", sum/count; else print "N/A" }' "$score_log")
        printf "  %s: %s/100\n" "$day" "$avg"
    done
fi
echo ""

echo "── DISK USAGE TREND (root /) ───────────────────────────────"
for i in 6 5 4 3 2 1 0; do
    local day
    day=$(date -d "${i} days ago" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
    local disk_file="${DATA_DIR}/metrics/disk_${day}.tsv"
    if [[ -f "$disk_file" ]]; then
        local pct
        pct=$(grep $'\t/\t' "$disk_file" 2>/dev/null | tail -1 | awk -F'\t' '{print $8}')
        printf "  %s: %s%% used\n" "$day" "${pct:-N/A}"
    else
        printf "  %s: No data\n" "$day"
    fi
done
echo ""

echo "── ALERT COUNT BY DAY ───────────────────────────────────────"
for i in 6 5 4 3 2 1 0; do
    local day
    day=$(date -d "${i} days ago" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
    local count
    count=$(grep "$day" "${LOG_DIR}/alerts.log" 2>/dev/null | wc -l || echo 0)
    printf "  %s: %d alerts\n" "$day" "$count"
done
echo ""
echo "══════════════════════════════════════════════════════════════"
} > "$REPORT_FILE"

cat "$REPORT_FILE"
log_info "Weekly report saved: ${REPORT_FILE}"

if [[ -n "${ALERT_EMAIL_TO}" && "${EMAIL_WEEKLY_REPORT:-true}" == "true" ]]; then
    command -v mail &>/dev/null && \
    mail -s "[${HOSTNAME}] Weekly Trend Report — ${WEEK_END}" "$ALERT_EMAIL_TO" < "$REPORT_FILE" 2>/dev/null
fi

log_end 0
