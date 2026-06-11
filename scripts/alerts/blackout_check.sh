#!/usr/bin/env bash
# =============================================================
# blackout_check.sh — Maintenance Window (Alert Suppression)
# =============================================================
# WHY: During planned maintenance (OS patches, deployments,
#      database migrations), systems deliberately show high
#      CPU, disk activity, and service restarts. Without
#      blackout windows, you get flooded with false alerts
#      during maintenance that mask real problems.
#
# HOW IT WORKS:
#   - Blackout windows defined in config/blackout.conf
#   - This script checks if the current time falls within any window
#   - Returns 0 (suppress) if in blackout, 1 (allow) if not
#   - checker.sh calls this before dispatching every alert
#
# CONFIG FORMAT (config/blackout.conf):
#   # day_of_week start_time end_time description
#   # day: 0=Sunday, 1=Monday ... 6=Saturday, *=every day
#   # time: HH:MM (24-hour)
#   BLACKOUT_WINDOWS=(
#     "6 02:00 04:00 Weekly maintenance window"
#     "* 00:00 00:05 Cron reboot window"
#   )
#
#   # For ad-hoc blackouts, also check BLACKOUT_ACTIVE flag:
#   # Set BLACKOUT_ACTIVE=true in .env to enable immediately
#
# USAGE:
#   bash scripts/alerts/blackout_check.sh
#   # Returns 0 if in blackout (suppress alerts)
#   # Returns 1 if not in blackout (allow alerts)
# =============================================================

SCRIPT_NAME="blackout_check.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"

# =============================================================
# FUNCTION: Check if current time is in a blackout window
# =============================================================
is_in_blackout() {
    # --- Method 1: BLACKOUT_ACTIVE flag (immediate/ad-hoc) ---
    # Set this in .env when starting maintenance: BLACKOUT_ACTIVE=true
    if [[ "${BLACKOUT_ACTIVE:-false}" == "true" ]]; then
        log_info "Blackout active: BLACKOUT_ACTIVE=true is set in config"
        return 0  # In blackout — suppress
    fi

    # --- Method 2: Blackout until specific timestamp ---
    # Set BLACKOUT_UNTIL="2026-05-20 04:00:00" for time-bounded maintenance
    if [[ -n "${BLACKOUT_UNTIL}" ]]; then
        local now
        now="$(date '+%Y-%m-%d %H:%M:%S')"
        if [[ "$now" < "$BLACKOUT_UNTIL" ]]; then
            log_info "Blackout active until ${BLACKOUT_UNTIL}"
            return 0  # In blackout
        fi
    fi

    # --- Method 3: Scheduled recurring windows ---
    # BLACKOUT_WINDOWS array from config/blackout.conf
    if [[ ${#BLACKOUT_WINDOWS[@]} -eq 0 ]]; then
        return 1  # No windows configured — not in blackout
    fi

    # Get current day-of-week (0=Sunday, 6=Saturday) and time
    local current_dow
    current_dow=$(date '+%w')  # 0-6
    local current_time
    current_time=$(date '+%H:%M')

    for window in "${BLACKOUT_WINDOWS[@]:-}"; do
        [[ -z "$window" || "$window" =~ ^# ]] && continue

        # Parse: "day start_time end_time description"
        local win_day win_start win_end win_desc
        read -r win_day win_start win_end win_desc <<< "$window"

        # Check day of week match (* = any day)
        local day_matches=false
        if [[ "$win_day" == "*" || "$win_day" == "$current_dow" ]]; then
            day_matches=true
        fi

        if [[ "$day_matches" == "true" ]]; then
            # Check time range: start <= current_time <= end
            # String comparison works for HH:MM format (lexicographic order)
            if [[ "$current_time" >= "$win_start" && "$current_time" <= "$win_end" ]]; then
                log_info "Blackout window active: '${win_desc:-unnamed}' (${win_start}–${win_end})"
                return 0  # In blackout — suppress
            fi
        fi
    done

    return 1  # Not in any blackout window
}

# =============================================================
# MAIN
# =============================================================
main() {
    if is_in_blackout; then
        # Exit 0 = in blackout = suppress alerts
        log_debug "Blackout check: IN blackout window — alerts suppressed"
        exit 0
    else
        # Exit 1 = not in blackout = allow alerts
        log_debug "Blackout check: NOT in blackout window — alerts allowed"
        exit 1
    fi
}

# --- Special commands for managing blackout state ---
case "${1:-}" in
    enable)
        # Enable immediate blackout
        echo "BLACKOUT_ACTIVE=true" >> "${PROJECT_ROOT}/.env"
        echo "Blackout enabled. Set BLACKOUT_ACTIVE=false in .env to disable."
        ;;
    disable)
        # Disable immediate blackout
        sed -i '/^BLACKOUT_ACTIVE=/d' "${PROJECT_ROOT}/.env" 2>/dev/null
        echo "BLACKOUT_ACTIVE=false" >> "${PROJECT_ROOT}/.env"
        echo "Blackout disabled."
        ;;
    until)
        # Set timed blackout: ./blackout_check.sh until "2026-05-20 04:00:00"
        local until_time="$2"
        sed -i '/^BLACKOUT_UNTIL=/d' "${PROJECT_ROOT}/.env" 2>/dev/null
        echo "BLACKOUT_UNTIL=${until_time}" >> "${PROJECT_ROOT}/.env"
        echo "Blackout enabled until: ${until_time}"
        ;;
    status)
        if is_in_blackout; then
            echo "Status: IN blackout window — alerts are suppressed"
        else
            echo "Status: NOT in blackout — alerts are active"
        fi
        ;;
    *)
        main
        ;;
esac
