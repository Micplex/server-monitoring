#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../core/config_loader.sh"
source "$D/../core/logger.sh"
source "$D/../core/metrics_writer.sh"
MONITOR_SERVICES="${MONITOR_SERVICES:-ssh cron}"
for svc in $MONITOR_SERVICES; do
  state=$(systemctl show "$svc" --property=ActiveState --value 2>/dev/null || echo "unknown")
  write_metric service "$svc" "$state"
  log_info "Service $svc: $state"
done
