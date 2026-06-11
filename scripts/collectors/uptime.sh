#!/usr/bin/env bash
# =============================================================
# uptime.sh — System Uptime & Boot History Collector
# =============================================================
# WHY: Unexpected reboots are a critical incident. A server that
#      was up for 200 days and suddenly shows 2 minutes of uptime
#      means something (kernel panic, OOM kill, power loss, or an
#      attacker) rebooted it. Tracking uptime catches this.
#
# WHAT WE TRACK:
#   - Current uptime in seconds (monotonic from /proc/uptime)
#   - Last boot time (human-readable and epoch)
#   - Recent reboot detection (uptime < threshold = recent reboot)
#   - Number of logged-in users (sudden drop could signal issues)
#   - System hostname and kernel version
#
# DATA SOURCE:
#   /proc/uptime   — seconds since last boot (monotonic, no drift)
#   who -b         — last boot time
#   uname -r       — kernel version
#   who | wc -l    — number of logged-in users
#
# TSV OUTPUT COLUMNS:
#   1: timestamp
#   2: hostname
#   3: uptime_seconds   — Raw uptime in seconds
#   4: uptime_human     — Human-readable (e.g., "5d 3h 22m")
#   5: boot_timestamp   — When system last booted (YYYY-MM-DD HH:MM:SS)
#   6: logged_in_users  — Number of currently logged-in users
#   7: kernel_version   — Linux kernel version string
# =============================================================

SCRIPT_NAME="uptime.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"
source "${CORE_DIR}/metrics_writer.sh"
source "${CORE_DIR}/lock_manager.sh"

acquire_lock "collector_uptime" || exit 0
log_start

# =============================================================
# FUNCTION: Convert seconds to human-readable uptime string
# =============================================================
# Input: 456789 (seconds)
# Output: "5d 6h 53m"
format_uptime() {
    local total_seconds="$1"
    local days=$(( total_seconds / 86400 ))
    local hours=$(( (total_seconds % 86400) / 3600 ))
    local minutes=$(( (total_seconds % 3600) / 60 ))

    if (( days > 0 )); then
        echo "${days}d ${hours}h ${minutes}m"
    elif (( hours > 0 )); then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

main() {
    log_info "Collecting uptime metrics"

    # /proc/uptime: "456789.12 345678.90"
    # First field = seconds since boot (can be float — we truncate)
    local uptime_seconds
    uptime_seconds=$(awk '{print int($1)}' /proc/uptime)

    local uptime_human
    uptime_human="$(format_uptime "$uptime_seconds")"

    # Get last boot time from `who -b` (boot time line)
    # Output format: "system boot  2026-05-14 08:23"
    local boot_timestamp
    boot_timestamp=$(who -b 2>/dev/null | awk '{print $3, $4}')
    # Fallback: calculate from current time minus uptime
    if [[ -z "$boot_timestamp" ]]; then
        boot_timestamp=$(date -d "@$(( $(date +%s) - uptime_seconds ))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    fi

    # Count logged-in users
    local logged_in_users
    logged_in_users=$(who 2>/dev/null | wc -l || echo 0)

    # Get kernel version
    local kernel_version
    kernel_version=$(uname -r 2>/dev/null || echo "unknown")

    log_info "Uptime: ${uptime_human} (${uptime_seconds}s) | Boot: ${boot_timestamp} | Users: ${logged_in_users}"
    log_info "Kernel: ${kernel_version}"

    # Alert on very recent reboot (< 10 minutes)
    # WHY: Short uptime in a production server is a red flag
    local reboot_alert_threshold="${RECENT_REBOOT_THRESHOLD_SECONDS:-600}"
    if (( uptime_seconds < reboot_alert_threshold )); then
        local uptime_min=$(( uptime_seconds / 60 ))
        log_warn "ALERT: System was recently rebooted! Uptime is only ${uptime_min} minutes"
        log_warn "Last boot: ${boot_timestamp}"
    fi

    write_metric "uptime" \
        "$uptime_seconds" \
        "$uptime_human" \
        "$boot_timestamp" \
        "$logged_in_users" \
        "$kernel_version"

    log_end 0
}

main "$@"
