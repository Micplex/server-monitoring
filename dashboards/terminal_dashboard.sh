#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../scripts/core/config_loader.sh" 2>/dev/null || true
source "$D/../scripts/core/metrics_reader.sh" 2>/dev/null || true
CPU=$(get_latest_value cpu 2 2>/dev/null || echo "N/A")
MEM=$(get_latest_value memory 2 2>/dev/null || echo "N/A")
SCORE=$(get_latest_value health_score 3 2>/dev/null || echo "N/A")
clear
echo "╔══════════════════════════════════════╗"
echo "║  LINUX MONITORING SUITE — DASHBOARD  ║"
echo "╚══════════════════════════════════════╝"
printf "  Host: %-20s Time: %s\n" "$(hostname -s 2>/dev/null)" "$(date '+%H:%M:%S')"
echo "  ──────────────────────────────────────"
printf "  CPU: %-5s%%    Memory: %-5s%%\n" "$CPU" "$MEM"
printf "  Health Score: %s/100\n" "$SCORE"
echo "╚══════════════════════════════════════╝"
