#!/usr/bin/env bash
P="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
run_test(){ local name="$1" cmd="$2"
  if bash -c "$cmd" &>/dev/null; then echo "✓ $name"; ((PASS++))
  else echo "✗ $name FAILED"; ((FAIL++)); fi
}
run_test "config_loader"   "source $P/scripts/core/config_loader.sh"
run_test "logger"          "source $P/scripts/core/logger.sh"
run_test "lock_manager"    "source $P/scripts/core/lock_manager.sh"
run_test "metrics_writer"  "source $P/scripts/core/metrics_writer.sh"
run_test "metrics_reader"  "source $P/scripts/core/metrics_reader.sh"
run_test "cpu_collector"   "bash $P/scripts/collectors/cpu.sh"
run_test "memory_collector" "bash $P/scripts/collectors/memory.sh"
run_test "disk_collector"  "bash $P/scripts/collectors/disk.sh"
run_test "health_score"    "bash $P/scripts/alerts/health_score.sh"
run_test "daily_report"    "bash $P/scripts/reports/daily.sh"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
