#!/usr/bin/env bash
# =============================================================
# html_dashboard.sh — Generate HTML Snapshot Dashboard
# =============================================================
# WHY: A simple HTML file that shows current system status.
#      No web server needed — just open it in a browser.
#      Perfect for client demos and quick status checks.
#      Generated every hour, viewable via any file server or sftp.
# =============================================================

SCRIPT_NAME="html_dashboard.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"
source "${CORE_DIR}/metrics_reader.sh"

HOSTNAME="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
OUTPUT_FILE="${DATA_DIR}/reports/dashboard.html"
TEMPLATE="${PROJECT_ROOT}/dashboards/html/template.html"

log_start

# Gather latest metrics
CPU_PCT=$(get_latest_value "cpu" 3 || echo "N/A")
MEM_PCT=$(get_latest_value "memory" 6 || echo "N/A")
SWAP_PCT=$(get_latest_value "memory" 11 || echo "N/A")
LOAD_1M=$(get_latest_value "load" 3 || echo "N/A")

# Get health score
HEALTH_SCORE=$(tail -1 "${DATA_DIR}/reports/health_scores.tsv" 2>/dev/null | awk -F'\t' '{print $3}' || echo "N/A")

# Determine status color based on value
color_for_pct() {
    local val="${1:-0}"
    local int_val
    int_val=$(printf "%.0f" "$val" 2>/dev/null || echo 0)
    if (( int_val >= 90 )); then echo "#dc3545"   # Red
    elif (( int_val >= 75 )); then echo "#fd7e14"  # Orange
    elif (( int_val >= 50 )); then echo "#ffc107"  # Yellow
    else echo "#28a745"                             # Green
    fi
}

CPU_COLOR=$(color_for_pct "$CPU_PCT")
MEM_COLOR=$(color_for_pct "$MEM_PCT")

# Count active alerts
ACTIVE_ALERTS=$(grep "$(date '+%Y-%m-%d')" "${LOG_DIR}/alerts.log" 2>/dev/null | wc -l || echo 0)

cat > "$OUTPUT_FILE" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="refresh" content="300">
<title>System Dashboard — ${HOSTNAME}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', monospace; background: #0d1117; color: #c9d1d9; }
  .header { background: #161b22; padding: 20px 30px; border-bottom: 1px solid #30363d; }
  .header h1 { color: #58a6ff; font-size: 1.5em; }
  .header .meta { color: #8b949e; font-size: 0.85em; margin-top: 5px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 16px; padding: 20px; }
  .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; }
  .card h3 { font-size: 0.8em; text-transform: uppercase; color: #8b949e; letter-spacing: 1px; margin-bottom: 12px; }
  .metric { font-size: 2.5em; font-weight: bold; }
  .bar-wrap { background: #21262d; border-radius: 4px; height: 8px; margin-top: 8px; }
  .bar { height: 8px; border-radius: 4px; transition: width 0.3s; }
  .label { font-size: 0.75em; color: #8b949e; margin-top: 6px; }
  .alerts-table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
  .alerts-table td, .alerts-table th { padding: 8px 12px; border-bottom: 1px solid #21262d; text-align: left; }
  .critical { color: #f85149; }
  .warning { color: #e3b341; }
  .good { color: #3fb950; }
  .section { padding: 0 20px 20px; }
  .section h2 { color: #58a6ff; margin-bottom: 12px; font-size: 1em; border-bottom: 1px solid #30363d; padding-bottom: 8px; }
  footer { text-align: center; padding: 16px; color: #8b949e; font-size: 0.75em; border-top: 1px solid #30363d; }
</style>
</head>
<body>
<div class="header">
  <h1>🖥️ System Dashboard — ${HOSTNAME}</h1>
  <div class="meta">Last updated: ${TIMESTAMP} | Environment: ${ENVIRONMENT:-production} | Auto-refreshes every 5 minutes</div>
</div>

<div class="grid">
  <div class="card">
    <h3>CPU Usage</h3>
    <div class="metric" style="color: ${CPU_COLOR}">${CPU_PCT}%</div>
    <div class="bar-wrap"><div class="bar" style="width:${CPU_PCT}%; background:${CPU_COLOR}"></div></div>
    <div class="label">Load: ${LOAD_1M} (1m avg)</div>
  </div>
  <div class="card">
    <h3>Memory Usage</h3>
    <div class="metric" style="color: ${MEM_COLOR}">${MEM_PCT}%</div>
    <div class="bar-wrap"><div class="bar" style="width:${MEM_PCT}%; background:${MEM_COLOR}"></div></div>
    <div class="label">Swap: ${SWAP_PCT}%</div>
  </div>
  <div class="card">
    <h3>Health Score</h3>
    <div class="metric" style="color:#58a6ff">${HEALTH_SCORE}<span style="font-size:0.4em">/100</span></div>
    <div class="label">Composite system health</div>
  </div>
  <div class="card">
    <h3>Alerts Today</h3>
    <div class="metric $(( ACTIVE_ALERTS > 0 )) && echo 'critical' || echo 'good'">${ACTIVE_ALERTS}</div>
    <div class="label">Fired in last 24 hours</div>
  </div>
</div>

<div class="section">
  <h2>📊 Disk Usage</h2>
  <div class="grid">
EOF

# Add disk cards
local disk_file="${DATA_DIR}/metrics/disk_$(date '+%Y-%m-%d').tsv"
if [[ -f "$disk_file" ]]; then
    awk -F'\t' '{ mounts[$4] = $8 } END {
        for (m in mounts) {
            pct = mounts[m]+0
            color = (pct>=95) ? "#f85149" : (pct>=80) ? "#e3b341" : "#3fb950"
            printf "    <div class=\"card\"><h3>%s</h3><div class=\"metric\" style=\"color:%s\">%s%%</div><div class=\"bar-wrap\"><div class=\"bar\" style=\"width:%s%%;background:%s\"></div></div></div>\n", m, color, pct, pct, color
        }
    }' "$disk_file" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << EOF
  </div>
</div>

<div class="section">
  <h2>🔔 Recent Alerts (Today)</h2>
  <table class="alerts-table">
    <tr><th>Time</th><th>Severity</th><th>Type</th><th>Message</th></tr>
EOF

grep "$(date '+%Y-%m-%d')" "${LOG_DIR}/alerts.log" 2>/dev/null | tail -20 | \
while read -r line; do
    local sev
    sev=$(echo "$line" | grep -o "\[CRITICAL\]\|\[WARNING\]" | tr -d '[]' | tr '[:upper:]' '[:lower:]')
    echo "    <tr class=\"${sev}\"><td colspan=\"4\">${line}</td></tr>" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" << EOF
  </table>
</div>

<footer>Linux Monitoring Suite | ${HOSTNAME} | Generated ${TIMESTAMP}</footer>
</body>
</html>
EOF

log_info "HTML dashboard generated: ${OUTPUT_FILE}"
log_end 0
