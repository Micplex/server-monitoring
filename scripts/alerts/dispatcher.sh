#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../core/config_loader.sh" 2>/dev/null || true
SEV="$1"; METRIC="$2"; VAL="$3"; THRESH="$4"
MSG="[${SEV}] ${METRIC}=${VAL} (threshold=${THRESH}) on $(hostname) at $(date)"
# Slack
if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
  curl -sS -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\"$MSG\"}" "$SLACK_WEBHOOK_URL" &
fi
# Email
if [[ -n "$ALERT_EMAIL" ]] && command -v mail &>/dev/null; then
  echo "$MSG" | mail -s "[$SEV] $METRIC alert" "$ALERT_EMAIL"
fi
# PagerDuty
if [[ -n "$PAGERDUTY_ROUTING_KEY" ]]; then
  curl -sS -X POST -H "Content-Type: application/json" \
    -d "{\"routing_key\":\"${PAGERDUTY_ROUTING_KEY}\",\"event_action\":\"trigger\",\"payload\":{\"summary\":\"${MSG}\",\"severity\":\"$(echo $SEV|tr A-Z a-z)\",\"source\":\"$(hostname)\"}}" \
    "https://events.pagerduty.com/v2/enqueue" &
fi
echo "$MSG" >> "${LOG_DIR:-/tmp}/alerts.log"
