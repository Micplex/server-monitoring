#!/usr/bin/env bash
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../core/config_loader.sh"
source "$D/../core/logger.sh"
source "$D/../core/metrics_writer.sh"
declare -A mi
while IFS=': ' read k v _; do mi["$k"]="${v//[^0-9]/}"; done < /proc/meminfo
total=${mi[MemTotal]}; free=${mi[MemFree]}; avail=${mi[MemAvailable]}
buffers=${mi[Buffers]}; cached=${mi[Cached]}
swap_total=${mi[SwapTotal]}; swap_free=${mi[SwapFree]}
[[ $total -eq 0 ]] && total=1
used=$(( total - avail ))
ram_pct=$(( used * 100 / total ))
avail_mb=$(( avail / 1024 ))
used_mb=$(( used / 1024 ))
total_mb=$(( total / 1024 ))
swap_used=0; swap_pct=0
if [[ $swap_total -gt 0 ]]; then
  swap_used=$(( swap_total - swap_free ))
  swap_pct=$(( swap_used * 100 / swap_total ))
fi
write_metric memory "$ram_pct" "$total_mb" "$used_mb" "$avail_mb" "$swap_pct" "${mi[MemFree]}"
log_info "Memory: ${ram_pct}% (${used_mb}MB/${total_mb}MB) swap=${swap_pct}%"
