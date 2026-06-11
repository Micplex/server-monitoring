#!/usr/bin/env bash
P="$(cd "$(dirname "$0")/.." && pwd)"
sed "s|/opt/monitoring|${P}|g" "$P/cron/crontab.template" > /tmp/mon_cron.tmp
(crontab -l 2>/dev/null; cat /tmp/mon_cron.tmp) | crontab -
echo "Cron jobs installed. Verify: crontab -l"
