#!/usr/bin/env bash
# =============================================================
# trend_detector.sh — Rising Trend Alert System
# =============================================================
# WHY: Threshold alerts are reactive — they fire when you're
#      already in trouble. Trend detection is PROACTIVE — it
#      alerts when metrics are consistently climbing toward a
#      threshold, giving you 30-60 minutes to act before
#      the system hits a crisis.
#
# EXAMPLE:
#   CPU is at 68%, 74%, 82% over the last 3 collections.
#   Threshold is 80% CRITICAL. Threshold alert hasn't fired yet.
#   Trend alert fires: "CPU is rising fast, currently 82%"
#   You investigate BEFORE it hits 95% and impacts users.
#
# ALGORITHM (Linear Regression Slope):
#   - Take last N samples of a metric (default: 3)
#   - Calculate the slope (rate of change per sample)
#   - If slope is consistently positive AND value is above
#     a "concern threshold" → fire a trend alert
#
# TREND STATES:
#   RISING  — Each sample higher than previous (consistent increase)
#   FALLING — Each sample lower than previous (recovering)
#   STABLE  — No consistent direction (noise / stable)
#
# USAGE:
#   bash scripts/alerts/trend_detector.sh
#   (Called by checker.sh after threshold checks)
# =============================================================

SCRIPT_NAME="trend_detector.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"
source "${CORE_DIR}/metrics_reader.sh"

# Number of recent samples to use for trend analysis
TREND_SAMPLES="${TREND_SAMPLES:-3}"

# Minimum slope to consider a trend "significant" (units per sample)
TREND_SLOPE_THRESHOLD="${TREND_SLOPE_THRESHOLD:-5}"

# Only alert on trends when value is above this % of the warning threshold
# Prevents trend alerts when system is completely healthy (e.g., CPU at 2%)
TREND_MIN_VALUE_PCT="${TREND_MIN_VALUE_PCT:-50}"

# =============================================================
# FUNCTION: Calculate linear regression slope for a series
# =============================================================
# Input: space-separated values, e.g., "72.1 78.4 85.2"
# Output: slope (positive = rising, negative = falling)
# WHY: Simple slope calculation (least squares line) gives a
#      stable trend signal even with noisy data. Better than
#      just comparing last vs. first sample.
calculate_slope() {
    local values="$1"
    echo "$values" | awk '{
        n = split($0, v, " ")
        if (n < 2) { print "0"; exit }

        # Least squares linear regression: slope = (n*Σxy - Σx*Σy) / (n*Σx² - (Σx)²)
        sum_x = 0; sum_y = 0; sum_xy = 0; sum_x2 = 0
        for (i = 1; i <= n; i++) {
            x = i
            y = v[i] + 0  # Convert to number
            sum_x  += x
            sum_y  += y
            sum_xy += x * y
            sum_x2 += x * x
        }
        denom = n * sum_x2 - sum_x * sum_x
        if (denom == 0) { print "0"; exit }
        slope = (n * sum_xy - sum_x * sum_y) / denom
        printf "%.2f\n", slope
    }'
}

# =============================================================
# FUNCTION: Analyze trend for a metric
# =============================================================
# Returns: "RISING slope current" | "FALLING slope current" | "STABLE slope current"
analyze_trend() {
    local metric_type="$1"
    local field_num="$2"         # TSV column number for the value
    local samples="${3:-$TREND_SAMPLES}"

    # Get last N values as space-separated list
    local values
    values="$(get_last_n_values "$metric_type" "$field_num" "$samples")"

    # Need at least 2 values to calculate a trend
    local value_count
    value_count=$(echo "$values" | wc -w)
    if (( value_count < 2 )); then
        echo "STABLE 0 0"
        return
    fi

    # Get the most recent value
    local current_value
    current_value=$(echo "$values" | awk '{print $NF}')

    # Calculate slope
    local slope
    slope="$(calculate_slope "$values")"

    # Determine trend direction based on slope magnitude
    local slope_int
    slope_int=$(printf "%.0f" "${slope#-}")  # Absolute value as int

    local direction
    direction=$(awk -v s="$slope" -v t="${TREND_SLOPE_THRESHOLD:-5}" '
        BEGIN {
            if (s >= t) print "RISING"
            else if (s <= -t) print "FALLING"
            else print "STABLE"
        }')

    echo "$direction $slope $current_value"
}

# =============================================================
# FUNCTION: Check trend for CPU and alert if rising
# =============================================================
check_cpu_trend() {
    # Column 3 = cpu_user_pct in cpu.sh TSV output
    local result
    result="$(analyze_trend 'cpu' 3)"
    read -r direction slope current <<< "$result"

    log_info "CPU trend: ${direction} (slope=${slope}/sample, current=${current}%)"

    local warn_threshold="${CPU_WARNING:-80}"
    local min_value
    min_value=$(awk -v t="$warn_threshold" -v p="${TREND_MIN_VALUE_PCT:-50}" \
                'BEGIN { printf "%.0f", t * p / 100 }')

    local current_int
    current_int=$(printf "%.0f" "${current:-0}")

    if [[ "$direction" == "RISING" ]] && (( current_int >= min_value )); then
        bash "${SCRIPT_DIR}/dispatcher.sh" \
            --type "cpu_trend" \
            --severity "WARNING" \
            --message "CPU trend RISING: ${current}% and climbing at ${slope}%/sample — may reach threshold soon" \
            --runbook "docs/alert-runbooks/cpu-high.md"
        log_warn "CPU rising trend alert dispatched: ${current}% slope=${slope}"
    fi
}

# =============================================================
# FUNCTION: Check trend for Memory
# =============================================================
check_memory_trend() {
    # Column 6 = used_pct in memory.sh TSV output
    local result
    result="$(analyze_trend 'memory' 6)"
    read -r direction slope current <<< "$result"

    log_info "Memory trend: ${direction} (slope=${slope}/sample, current=${current}%)"

    local warn_threshold="${RAM_WARNING:-80}"
    local min_value
    min_value=$(awk -v t="$warn_threshold" -v p="${TREND_MIN_VALUE_PCT:-50}" \
                'BEGIN { printf "%.0f", t * p / 100 }')

    local current_int
    current_int=$(printf "%.0f" "${current:-0}")

    if [[ "$direction" == "RISING" ]] && (( current_int >= min_value )); then
        bash "${SCRIPT_DIR}/dispatcher.sh" \
            --type "memory_trend" \
            --severity "WARNING" \
            --message "Memory usage trend RISING: ${current}% and climbing — investigate memory leaks" \
            --runbook "docs/alert-runbooks/disk-full.md"
        log_warn "Memory rising trend alert dispatched: ${current}% slope=${slope}"
    fi
}

# =============================================================
# FUNCTION: Check trend for Disk (root filesystem)
# =============================================================
check_disk_trend() {
    # Column 8 = use_pct in disk.sh TSV output (for root /)
    local disk_file="${DATA_DIR}/metrics/disk_$(date '+%Y-%m-%d').tsv"
    [[ ! -f "$disk_file" ]] && return

    # Get the last N use_pct values for the root (/) filesystem
    local values
    values=$(grep $'\t/\t' "$disk_file" 2>/dev/null | \
             tail -n "$TREND_SAMPLES" | \
             awk -F'\t' '{print $8}' | \
             tr '\n' ' ')

    [[ -z "$values" ]] && return

    local slope
    slope="$(calculate_slope "$values")"
    local current
    current=$(echo "$values" | awk '{print $NF}')

    local direction
    direction=$(awk -v s="$slope" -v t="${TREND_SLOPE_THRESHOLD:-2}" '
        BEGIN {
            if (s >= t) print "RISING"
            else if (s <= -t) print "FALLING"
            else print "STABLE"
        }')

    log_info "Disk (/) trend: ${direction} (slope=${slope}/sample, current=${current}%)"

    local current_int
    current_int=$(printf "%.0f" "${current:-0}")
    local min_value="${DISK_TREND_MIN:-60}"

    if [[ "$direction" == "RISING" ]] && (( current_int >= min_value )); then
        bash "${SCRIPT_DIR}/dispatcher.sh" \
            --type "disk_trend" \
            --severity "WARNING" \
            --message "Disk (/) usage trend RISING: ${current}% — at this rate, may fill in hours" \
            --runbook "docs/alert-runbooks/disk-full.md"
        log_warn "Disk rising trend alert dispatched: ${current}% slope=${slope}"
    fi
}

# =============================================================
# MAIN
# =============================================================
main() {
    log_info "Running trend analysis (${TREND_SAMPLES} samples, slope threshold=${TREND_SLOPE_THRESHOLD})"

    check_cpu_trend
    check_memory_trend
    check_disk_trend

    log_info "Trend analysis complete"
}

main "$@"
