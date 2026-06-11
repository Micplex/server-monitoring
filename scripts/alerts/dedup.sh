#!/usr/bin/env bash
# =============================================================
# dedup.sh — Alert Deduplication Engine
# =============================================================
# WHY: Without deduplication, a single problem (e.g., CPU is high)
#      generates an alert every 5 minutes — 12 alerts per hour,
#      288 per day. Alert fatigue makes teams ignore everything.
#      Deduplication ensures the same alert fires at most once
#      per configurable cooldown period.
#
# MECHANISM:
#   - Stores alert history in data/alerts/dedup_state.tsv
#   - "check" command: returns 0 (suppress) if alert fired recently
#   - "record" command: marks an alert as having just fired
#   - "clear" command: removes state for a resolved alert
#
# COOLDOWN LOGIC:
#   - CRITICAL alerts: resend after CRITICAL_RESEND_MINUTES (default 60)
#   - WARNING alerts:  resend after WARNING_RESEND_MINUTES (default 120)
#
# USAGE:
#   # Returns 0 if alert should be SUPPRESSED, 1 if it should fire
#   bash dedup.sh check "cpu" "CRITICAL"
#   
#   # Record that this alert was just sent
#   bash dedup.sh record "cpu" "CRITICAL"
#
#   # Clear alert state when issue resolves
#   bash dedup.sh clear "cpu" "CRITICAL"
# =============================================================

SCRIPT_NAME="dedup.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"

DEDUP_FILE="${DATA_DIR}/alerts/dedup_state.tsv"

# Cooldown periods in minutes (how long before same alert resends)
CRITICAL_RESEND_MINUTES="${CRITICAL_RESEND_MINUTES:-60}"
WARNING_RESEND_MINUTES="${WARNING_RESEND_MINUTES:-120}"

# =============================================================
# FUNCTION: Get cooldown minutes for a severity level
# =============================================================
get_cooldown() {
    local severity="$1"
    case "$severity" in
        CRITICAL) echo "$CRITICAL_RESEND_MINUTES" ;;
        WARNING)  echo "$WARNING_RESEND_MINUTES" ;;
        *)        echo "60" ;;
    esac
}

# =============================================================
# COMMAND: check — Should this alert be suppressed?
# =============================================================
# Returns 0 = SUPPRESS (already alerted recently)
# Returns 1 = ALLOW (not alerted recently, should fire)
cmd_check() {
    local alert_type="$1"
    local severity="$2"
    local cooldown
    cooldown="$(get_cooldown "$severity")"

    # If no dedup file exists, nothing is suppressed
    [[ ! -f "$DEDUP_FILE" ]] && return 1

    # Look for this alert_type+severity combination in the dedup file
    # Dedup file format: timestamp<TAB>alert_type<TAB>severity
    local last_fired
    last_fired=$(awk -F'\t' -v atype="$alert_type" -v sev="$severity" \
        '$2 == atype && $3 == sev { last = $1 } END { print last }' \
        "$DEDUP_FILE" 2>/dev/null)

    [[ -z "$last_fired" ]] && return 1  # Never fired, allow

    # Calculate cutoff time (now - cooldown minutes)
    local cutoff
    cutoff="$(date -d "${cooldown} minutes ago" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
             || date -v-${cooldown}M '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
             || echo "1970-01-01 00:00:00")"

    # If last_fired >= cutoff, alert is still within cooldown — SUPPRESS
    # String comparison works here because timestamp format is ISO 8601
    if [[ "$last_fired" > "$cutoff" || "$last_fired" == "$cutoff" ]]; then
        log_debug "Dedup SUPPRESS: [${alert_type}/${severity}] last fired at ${last_fired}, cooldown=${cooldown}min"
        return 0  # Suppress
    else
        log_debug "Dedup ALLOW: [${alert_type}/${severity}] cooldown expired at ${cutoff}"
        return 1  # Allow
    fi
}

# =============================================================
# COMMAND: record — Mark an alert as having just fired
# =============================================================
cmd_record() {
    local alert_type="$1"
    local severity="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    mkdir -p "$(dirname "$DEDUP_FILE")" 2>/dev/null

    # Remove any existing entry for this alert_type+severity
    # Then add the new timestamp
    if [[ -f "$DEDUP_FILE" ]]; then
        # Create temp file without the old entry
        local tmp_file
        tmp_file="$(mktemp)"
        awk -F'\t' -v atype="$alert_type" -v sev="$severity" \
            '$2 != atype || $3 != sev { print }' \
            "$DEDUP_FILE" > "$tmp_file"
        mv "$tmp_file" "$DEDUP_FILE"
    fi

    # Append new record
    printf '%s\t%s\t%s\n' "$timestamp" "$alert_type" "$severity" >> "$DEDUP_FILE"
    log_debug "Dedup recorded: [${alert_type}/${severity}] at ${timestamp}"
}

# =============================================================
# COMMAND: clear — Remove alert state (issue resolved)
# =============================================================
cmd_clear() {
    local alert_type="$1"
    local severity="${2:-}"  # Optional: clear all severities for this type

    [[ ! -f "$DEDUP_FILE" ]] && return 0

    local tmp_file
    tmp_file="$(mktemp)"

    if [[ -n "$severity" ]]; then
        # Clear specific type+severity combo
        awk -F'\t' -v atype="$alert_type" -v sev="$severity" \
            '$2 != atype || $3 != sev { print }' \
            "$DEDUP_FILE" > "$tmp_file"
        log_debug "Dedup cleared: [${alert_type}/${severity}]"
    else
        # Clear all entries for this alert_type
        awk -F'\t' -v atype="$alert_type" \
            '$2 != atype { print }' \
            "$DEDUP_FILE" > "$tmp_file"
        log_debug "Dedup cleared all severities for: [${alert_type}]"
    fi

    mv "$tmp_file" "$DEDUP_FILE"
}

# =============================================================
# COMMAND: status — Show all current dedup state
# =============================================================
cmd_status() {
    echo "=== Alert Deduplication State ==="
    if [[ ! -f "$DEDUP_FILE" ]]; then
        echo "  No alerts recorded yet."
        return 0
    fi

    printf '%-30s %-10s %-12s %s\n' "Alert Type" "Severity" "Last Fired" "Cooldown Remaining"
    echo "  ────────────────────────────────────────────────────────────────"

    while IFS=$'\t' read -r last_fired alert_type severity; do
        local cooldown
        cooldown="$(get_cooldown "$severity")"

        # Calculate remaining cooldown
        local last_epoch
        last_epoch=$(date -d "$last_fired" +%s 2>/dev/null || date -j -f '%Y-%m-%d %H:%M:%S' "$last_fired" +%s 2>/dev/null || echo 0)
        local now_epoch
        now_epoch=$(date +%s)
        local elapsed=$(( (now_epoch - last_epoch) / 60 ))
        local remaining=$(( cooldown - elapsed ))

        if (( remaining > 0 )); then
            printf '  %-28s %-10s %-20s %s min\n' \
                "$alert_type" "$severity" "$last_fired" "$remaining"
        else
            printf '  %-28s %-10s %-20s %s\n' \
                "$alert_type" "$severity" "$last_fired" "EXPIRED (ready to fire)"
        fi
    done < "$DEDUP_FILE"
}

# =============================================================
# COMMAND: cleanup — Remove stale entries older than 24 hours
# =============================================================
cmd_cleanup() {
    [[ ! -f "$DEDUP_FILE" ]] && return 0

    local cutoff
    cutoff="$(date -d '24 hours ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '1970-01-01 00:00:00')"

    local tmp_file
    tmp_file="$(mktemp)"
    awk -F'\t' -v cutoff="$cutoff" '$1 >= cutoff { print }' "$DEDUP_FILE" > "$tmp_file"
    mv "$tmp_file" "$DEDUP_FILE"
    log_debug "Dedup cleanup: removed entries older than 24h"
}

# =============================================================
# MAIN — Route to correct command
# =============================================================
COMMAND="${1:-status}"
ALERT_TYPE="${2:-}"
SEVERITY="${3:-}"

case "$COMMAND" in
    check)   cmd_check   "$ALERT_TYPE" "$SEVERITY" ;;
    record)  cmd_record  "$ALERT_TYPE" "$SEVERITY" ;;
    clear)   cmd_clear   "$ALERT_TYPE" "$SEVERITY" ;;
    status)  cmd_status ;;
    cleanup) cmd_cleanup ;;
    *)
        echo "Usage: dedup.sh {check|record|clear|status|cleanup} [alert_type] [severity]"
        exit 1
        ;;
esac
