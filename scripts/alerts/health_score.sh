#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../core/config_loader.sh"
source "$D/../core/metrics_reader.sh"
source "$D/../core/metrics_writer.sh"
score=100
cpu=$(get_latest_value cpu 2); mem=$(get_latest_value memory 2)
[[ -n "$cpu" ]] && [[ $cpu -ge 95 ]] && score=$((score-30))
[[ -n "$cpu" ]] && [[ $cpu -ge 80 ]] && [[ $cpu -lt 95 ]] && score=$((score-15))
[[ -n "$mem" ]] && [[ $mem -ge 95 ]] && score=$((score-30))
[[ -n "$mem" ]] && [[ $mem -ge 85 ]] && [[ $mem -lt 95 ]] && score=$((score-15))
[[ $score -lt 0 ]] && score=0
write_metric health_score "$(hostname)" "$score"
echo "Health Score: $score/100"
