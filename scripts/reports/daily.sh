#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../core/config_loader.sh"
source "$D/../core/metrics_reader.sh"
TODAY=$(date '+%Y-%m-%d')
cpu_avg=$(get_avg cpu 2 288)
mem_avg=$(get_avg memory 2 288)
alerts=$(wc -l < "${DATA_DIR}/metrics/alert_history_${TODAY}.tsv" 2>/dev/null || echo 0)
score=$(get_latest_value health_score 3)
echo "=============================="
echo " Daily Report — $TODAY"
echo "=============================="
echo " CPU avg:      ${cpu_avg}%"
echo " Memory avg:   ${mem_avg}%"
echo " Alerts fired: ${alerts}"
echo " Health score: ${score}/100"
echo "=============================="
