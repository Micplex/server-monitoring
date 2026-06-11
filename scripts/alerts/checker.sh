#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../core/config_loader.sh"
source "$D/../core/logger.sh"
source "$D/../core/metrics_reader.sh"
source "$D/../core/metrics_writer.sh"
CPU_WARNING="${CPU_WARNING:-80}"; CPU_CRITICAL="${CPU_CRITICAL:-95}"
RAM_WARNING="${RAM_WARNING:-85}"; RAM_CRITICAL="${RAM_CRITICAL:-95}"
DISK_WARNING="${DISK_WARNING:-80}"; DISK_CRITICAL="${DISK_CRITICAL:-95}"
alert(){
  local sev="$1" metric="$2" val="$3" thresh="$4"
  log_warn "ALERT [$sev] $metric=${val} threshold=${thresh}"
  write_metric alert_history "$sev" "$metric" "$val" "$thresh"
  bash "$D/dispatcher.sh" "$sev" "$metric" "$val" "$thresh" 2>/dev/null || true
}
cpu=$(get_latest_value cpu 2); mem=$(get_latest_value memory 2)
[[ -n "$cpu" ]] && [[ "$cpu" -ge "$CPU_CRITICAL" ]] && alert CRITICAL cpu_pct "$cpu" "$CPU_CRITICAL"
[[ -n "$cpu" ]] && [[ "$cpu" -ge "$CPU_WARNING" ]] && [[ "$cpu" -lt "$CPU_CRITICAL" ]] && alert WARNING cpu_pct "$cpu" "$CPU_WARNING"
[[ -n "$mem" ]] && [[ "$mem" -ge "$RAM_CRITICAL" ]] && alert CRITICAL ram_pct "$mem" "$RAM_CRITICAL"
[[ -n "$mem" ]] && [[ "$mem" -ge "$RAM_WARNING" ]] && [[ "$mem" -lt "$RAM_CRITICAL" ]] && alert WARNING ram_pct "$mem" "$RAM_WARNING"
log_info "Threshold check complete. CPU=${cpu}% RAM=${mem}%"
