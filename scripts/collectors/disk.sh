#!/usr/bin/env bash
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../core/config_loader.sh"
source "$D/../core/logger.sh"
source "$D/../core/metrics_writer.sh"
df -P --exclude-type=tmpfs --exclude-type=devtmpfs 2>/dev/null | tail -n+2 | while read fs size used avail pct mp; do
  pct_num="${pct//%/}"
  write_metric disk "$fs" "$mp" "$pct_num" "$size" "$used" "$avail"
  log_info "Disk $mp: ${pct_num}%"
done
