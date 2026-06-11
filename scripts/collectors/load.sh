#!/usr/bin/env bash
# =============================================================
# load.sh — System Load Average Collector
# =============================================================
# WHY: Load average is collected separately from CPU because it
#      measures DEMAND on the system, not just CPU usage.
#      A system can have 100% CPU usage AND high load, OR
#      low CPU usage with high load (I/O-bound workload).
#
# WHAT IS LOAD AVERAGE?
#   The number of processes that are RUNNABLE (waiting for CPU)
#   or UNINTERRUPTIBLE (waiting for disk I/O) averaged over time.
#
#   - Load 1.0 on a 1-core system   = 100% busy, no headroom
#   - Load 4.0 on a 4-core system   = 100% busy, no headroom
#   - Load 4.0 on a 1-core system   = system is overwhelmed (4x overloaded)
#   - Load 0.5 on a 4-core system   = system is lightly loaded (12.5% utilized)
#
# THREE TIME WINDOWS:
#   - 1 minute  → right now (spikes)
#   - 5 minutes → short-term trend
#   - 15 minutes → sustained load (most important for alerting)
#
# TSV OUTPUT COLUMNS:
#   1: timestamp
#   2: hostname
#   3: load_1m         — 1-minute load average
#   4: load_5m         — 5-minute load average
#   5: load_15m        — 15-minute load average
#   6: cpu_cores       — Number of logical CPU cores
#   7: load_per_core   — load_15m / cpu_cores (normalized)
#   8: running_procs   — Currently running processes
#   9: total_procs     — Total processes (running + sleeping + stopped)
# =============================================================

SCRIPT_NAME="load.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"
source "${CORE_DIR}/metrics_writer.sh"
source "${CORE_DIR}/lock_manager.sh"

acquire_lock "collector_load" || exit 0
log_start

main() {
    log_info "Collecting system load metrics"

    # /proc/loadavg format: load_1m load_5m load_15m running/total last_pid
    # Example: 0.15 0.25 0.30 1/234 14521
    local raw_load
    raw_load=$(cat /proc/loadavg)

    # Parse using awk — handles the running/total column cleanly
    local load_data
    load_data=$(echo "$raw_load" | awk '{
        split($4, proc_parts, "/")
        print $1, $2, $3, proc_parts[1], proc_parts[2]
    }')

    read -r load_1m load_5m load_15m running_procs total_procs <<< "$load_data"

    # Get CPU core count for normalization
    local cores
    cores=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo 1)

    # Calculate load per core — the key metric for alerting
    # WHY: A load of 8.0 is fine on a 16-core server but terrible on a 2-core one
    local load_per_core
    load_per_core=$(awk -v load="$load_15m" -v cores="$cores" \
                    'BEGIN { printf "%.2f", load/cores }')

    log_info "Load: ${load_1m} (1m) ${load_5m} (5m) ${load_15m} (15m) | ${cores} cores | ${load_per_core} per-core"
    log_info "Processes: ${running_procs} running / ${total_procs} total"

    # Alert thresholds (from config or sensible defaults)
    local load_warn="${LOAD_WARNING:-4}"
    local load_crit="${LOAD_CRITICAL:-8}"

    # Compare using awk (bash can't compare floats)
    local is_warning is_critical
    is_warning=$(awk -v load="$load_15m" -v cores="$cores" -v thresh="$load_warn" \
                 'BEGIN { print (load/cores >= thresh) ? "1" : "0" }')
    is_critical=$(awk -v load="$load_15m" -v cores="$cores" -v thresh="$load_crit" \
                  'BEGIN { print (load/cores >= thresh) ? "1" : "0" }')

    if [[ "$is_critical" == "1" ]]; then
        log_error "CRITICAL: Load per core is ${load_per_core} (threshold: ${load_crit})"
    elif [[ "$is_warning" == "1" ]]; then
        log_warn "Load per core is ${load_per_core} (threshold: ${load_warn})"
    fi

    write_metric "load" \
        "$load_1m" \
        "$load_5m" \
        "$load_15m" \
        "$cores" \
        "$load_per_core" \
        "$running_procs" \
        "$total_procs"

    log_end 0
}

main "$@"
