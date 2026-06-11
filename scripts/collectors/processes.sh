#!/usr/bin/env bash
# =============================================================
# processes.sh — Top Process & Zombie Detection Collector
# =============================================================
# WHY: A runaway process can consume 100% CPU or fill RAM while
#      the system "looks healthy" from a high level. You need
#      to know WHICH process is consuming resources.
#      Zombie processes indicate a programming bug in the parent
#      application and can eventually exhaust the process table.
#
# WHAT WE COLLECT:
#   - Top N processes by CPU consumption
#   - Top N processes by Memory consumption
#   - Zombie process count and their parent PIDs
#   - Total process count (sudden increases = fork bombs / DDoS)
#
# DATA SOURCE:
#   /proc/[pid]/stat  — per-process stats (kernel-accurate)
#   ps aux            — simpler, good enough for top-N monitoring
#   /proc/[pid]/status — process state, zombie detection
#
# TSV FILES WRITTEN:
#   processes_cpu_YYYY-MM-DD.tsv   — Top N by CPU
#   processes_mem_YYYY-MM-DD.tsv   — Top N by Memory
#   processes_zombie_YYYY-MM-DD.tsv — Zombie processes
# =============================================================

SCRIPT_NAME="processes.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"
source "${CORE_DIR}/metrics_writer.sh"
source "${CORE_DIR}/lock_manager.sh"

acquire_lock "collector_processes" || exit 0
log_start

# How many top processes to record (configurable)
TOP_PROCESS_COUNT="${TOP_PROCESS_COUNT:-10}"

# =============================================================
# FUNCTION: Collect top N processes by CPU usage
# =============================================================
collect_top_cpu() {
    log_info "Collecting top ${TOP_PROCESS_COUNT} processes by CPU"

    # ps flags:
    #   -e = all processes (not just current user)
    #   -o = output format
    #   --sort=-%cpu = sort by CPU descending (highest first)
    #   --no-headers = skip column header line
    # WHY ps? Because parsing /proc/[pid]/stat for hundreds of
    # processes is complex. ps aggregates it correctly.
    ps -eo pid,ppid,user,pcpu,pmem,vsz,rss,stat,comm \
        --sort=-%cpu \
        --no-headers \
        2>/dev/null | head -n "$TOP_PROCESS_COUNT" | \
    while read -r pid ppid user cpu_pct mem_pct vsz_kb rss_kb state comm; do
        # Convert VSZ and RSS from KB to MB
        local vsz_mb rss_mb
        vsz_mb=$(( vsz_kb / 1024 ))
        rss_mb=$(( rss_kb / 1024 ))

        write_metric "processes_cpu" \
            "$pid" \
            "$ppid" \
            "$user" \
            "$cpu_pct" \
            "$mem_pct" \
            "$vsz_mb" \
            "$rss_mb" \
            "$state" \
            "$comm"
    done

    # Log the #1 CPU consumer
    local top_proc
    top_proc=$(ps -eo pcpu,comm --sort=-%cpu --no-headers 2>/dev/null | head -1)
    local top_cpu top_name
    read -r top_cpu top_name <<< "$top_proc"
    log_info "Top CPU consumer: [${top_name}] at ${top_cpu}%"

    # Alert if top process exceeds threshold
    local proc_cpu_warn="${PROCESS_CPU_WARNING:-80}"
    local top_cpu_int
    top_cpu_int=$(printf "%.0f" "${top_cpu:-0}")
    if (( top_cpu_int >= proc_cpu_warn )); then
        log_warn "Process [${top_name}] consuming ${top_cpu}% CPU"
    fi
}

# =============================================================
# FUNCTION: Collect top N processes by Memory usage
# =============================================================
collect_top_memory() {
    log_info "Collecting top ${TOP_PROCESS_COUNT} processes by memory"

    ps -eo pid,ppid,user,pcpu,pmem,vsz,rss,stat,comm \
        --sort=-%mem \
        --no-headers \
        2>/dev/null | head -n "$TOP_PROCESS_COUNT" | \
    while read -r pid ppid user cpu_pct mem_pct vsz_kb rss_kb state comm; do
        local vsz_mb rss_mb
        vsz_mb=$(( vsz_kb / 1024 ))
        rss_mb=$(( rss_kb / 1024 ))

        write_metric "processes_mem" \
            "$pid" \
            "$ppid" \
            "$user" \
            "$cpu_pct" \
            "$mem_pct" \
            "$vsz_mb" \
            "$rss_mb" \
            "$state" \
            "$comm"
    done

    local top_proc
    top_proc=$(ps -eo pmem,rss,comm --sort=-%mem --no-headers 2>/dev/null | head -1)
    local top_mem top_rss top_name
    read -r top_mem top_rss top_name <<< "$top_proc"
    local top_rss_mb=$(( top_rss / 1024 ))
    log_info "Top memory consumer: [${top_name}] at ${top_mem}% (${top_rss_mb}MB RSS)"
}

# =============================================================
# FUNCTION: Detect and log zombie processes
# =============================================================
# A zombie (state 'Z') is a process that has finished but whose
# parent hasn't collected its exit status via wait().
# A few zombies are normal; many zombies = application bug.
detect_zombies() {
    log_info "Checking for zombie processes"

    # ps state 'Z' = zombie
    local zombie_list
    zombie_list=$(ps -eo pid,ppid,user,stat,comm \
                  --no-headers 2>/dev/null | awk '$4 ~ /Z/ {print}')

    local zombie_count
    zombie_count=$(echo "$zombie_list" | grep -c "." || echo 0)
    [[ -z "$zombie_list" ]] && zombie_count=0

    if (( zombie_count == 0 )); then
        log_info "No zombie processes found"
        write_metric "processes_zombie" "0" "none" "none" "none"
    else
        log_warn "Found ${zombie_count} zombie process(es)!"
        echo "$zombie_list" | while read -r pid ppid user state comm; do
            log_warn "  Zombie PID=${pid} PPID=${ppid} USER=${user} CMD=${comm}"
            write_metric "processes_zombie" \
                "$zombie_count" \
                "$pid" \
                "$ppid" \
                "$comm"
        done
    fi

    return "$zombie_count"
}

# =============================================================
# FUNCTION: Get total process count
# =============================================================
get_total_processes() {
    # wc -l counts lines; subtract 1 for the header
    local count
    count=$(ps -e --no-headers 2>/dev/null | wc -l)
    echo "${count:-0}"
}

# =============================================================
# MAIN
# =============================================================
main() {
    log_info "Collecting process metrics"

    local total_procs
    total_procs="$(get_total_processes)"
    log_info "Total processes: ${total_procs}"

    # Alert on very high process count (could indicate fork bomb)
    local proc_count_warn="${PROCESS_COUNT_WARNING:-500}"
    if (( total_procs > proc_count_warn )); then
        log_warn "Very high process count: ${total_procs} (threshold: ${proc_count_warn})"
    fi

    collect_top_cpu
    collect_top_memory
    detect_zombies

    log_end 0
}

main "$@"
