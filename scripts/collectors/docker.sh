#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../core/config_loader.sh"
source "$D/../core/logger.sh"
source "$D/../core/metrics_writer.sh"
command -v docker &>/dev/null || exit 0
docker ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null | while IFS=$'\t' read name status; do
  state="running"; [[ "$status" != *"Up"* ]] && state="stopped"
  write_metric docker "$name" "$state" "$status"
  log_info "Container $name: $state"
done
