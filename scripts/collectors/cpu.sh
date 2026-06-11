#!/usr/bin/env bash
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../core/config_loader.sh"
source "$D/../core/logger.sh"
source "$D/../core/metrics_writer.sh"
source "$D/../core/lock_manager.sh"
acquire_lock cpu || exit 0
trap "release_lock cpu" EXIT
read cpu user nice sys idle iowait irq softirq steal guest _ < /proc/stat
sleep 1
read cpu2 u2 n2 s2 i2 io2 ir2 so2 st2 g2 _ < /proc/stat
tot=$(( (u2+n2+s2+i2+io2+ir2+so2+st2) - (user+nice+sys+idle+iowait+irq+softirq+steal) ))
idl=$(( i2 - idle ))
[[ $tot -eq 0 ]] && tot=1
cpu_pct=$(( (tot - idl) * 100 / tot ))
cores=$(nproc 2>/dev/null || grep -c processor /proc/cpuinfo)
read la1 la5 la15 _ < /proc/loadavg
load_per_core=$(echo "$la1 $cores" | awk '{printf "%.2f",$1/$2}')
write_metric cpu "$cpu_pct" "$la1" "$la5" "$la15" "$cores" "$load_per_core"
log_info "CPU: ${cpu_pct}% load=${la1} cores=${cores}"
