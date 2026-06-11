#!/usr/bin/env bash
# Entrypoint — bash loop scheduler (no crond, works in Docker Desktop)
echo "[monitor] Linux Monitoring Suite starting..."
echo "[monitor] Collectors: every 5 min | Alerts: every 15 min | Report: every 6h"

COLLECT_INTERVAL=300    # 5 minutes
ALERT_INTERVAL=900      # 15 minutes
REPORT_INTERVAL=21600   # 6 hours

last_alert=0
last_report=0

while true; do
    now=$(date +%s)

    # Always run collectors
    bash /opt/monitoring/bin/monitor >> /opt/monitoring/logs/cron.log 2>&1

    # Run alert check every 15 min
    if (( now - last_alert >= ALERT_INTERVAL )); then
        bash /opt/monitoring/bin/alert-check >> /opt/monitoring/logs/cron.log 2>&1
        bash /opt/monitoring/scripts/alerts/health_score.sh >> /opt/monitoring/logs/cron.log 2>&1
        last_alert=$now
    fi

    # Run report every 6 hours
    if (( now - last_report >= REPORT_INTERVAL )); then
        bash /opt/monitoring/bin/report >> /opt/monitoring/logs/cron.log 2>&1
        last_report=$now
    fi

    echo "[monitor] $(date '+%Y-%m-%d %H:%M:%S') — cycle complete. Sleeping ${COLLECT_INTERVAL}s..."
    sleep $COLLECT_INTERVAL
done
