#!/usr/bin/env bash
# =============================================================
# self_test.sh — Verifies the monitoring stack itself is healthy
# =============================================================
# WHY: "Who watches the watchmen?" — Your monitoring system can
#      silently fail if cron breaks, disk fills up, or a collector
#      crashes. This self-test runs periodically to confirm all
#      components are working, then exits with a health score.
#
# CHECKS PERFORMED:
#   1. All collector scripts are executable
#   2. Collector data files were recently updated (not stale)
#   3. Log directory is writable and has space
#   4. Data directory is writable
#   5. Cron job is installed and active
#   6. Alert dispatcher script exists and is executable
#   7. Required config variables are set
#   8. Config files exist
#
# EXIT CODES:
#   0 = All healthy
#   1 = Some checks failed (check logs for details)
#
# USAGE:
#   ./bin/health
#   bash scripts/core/self_test.sh
# =============================================================

SCRIPT_NAME="self_test.sh"
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"
source "${CORE_DIR}/metrics_reader.sh"

COLLECTORS_DIR="${PROJECT_ROOT}/scripts/collectors"
ALERTS_DIR="${PROJECT_ROOT}/scripts/alerts"

# Self-test result tracking
_PASS=0
_FAIL=0
_WARN=0

# --- Print a test result line ---
_result() {
    local status="$1"  # PASS, FAIL, WARN
    local check="$2"
    local detail="${3:-}"

    case "$status" in
        PASS) echo -e "  \033[0;32m✓ PASS\033[0m  ${check}${detail:+ — ${detail}}";;
        FAIL) echo -e "  \033[0;31m✗ FAIL\033[0m  ${check}${detail:+ — ${detail}}";;
        WARN) echo -e "  \033[0;33m⚠ WARN\033[0m  ${check}${detail:+ — ${detail}}";;
    esac
}

_pass() { _result "PASS" "$@"; ((_PASS++)); }
_fail() { _result "FAIL" "$@"; ((_FAIL++)); log_error "Self-test FAIL: $1 ${2:-}"; }
_warn() { _result "WARN" "$@"; ((_WARN++)); log_warn "Self-test WARN: $1 ${2:-}"; }

# =============================================================
# CHECK 1: Collector scripts exist and are executable
# =============================================================
check_collectors() {
    echo ""
    echo "[ Collector Scripts ]"
    local collectors=(cpu memory disk load services docker uptime network processes)
    for collector in "${collectors[@]}"; do
        local script="${COLLECTORS_DIR}/${collector}.sh"
        if [[ -f "$script" && -x "$script" ]]; then
            _pass "${collector}.sh exists and is executable"
        elif [[ -f "$script" ]]; then
            _warn "${collector}.sh exists but is NOT executable" "run: chmod +x ${script}"
        else
            _fail "${collector}.sh missing" "expected at: ${script}"
        fi
    done
}

# =============================================================
# CHECK 2: Collector data files are fresh (updated recently)
# =============================================================
check_data_freshness() {
    echo ""
    echo "[ Metric Data Freshness (max ${COLLECTOR_STALE_MINUTES:-15} min) ]"
    local collectors=(cpu memory disk)
    local max_age="${COLLECTOR_STALE_MINUTES:-15}"

    for collector in "${collectors[@]}"; do
        if is_metric_fresh "$collector" "$max_age"; then
            local record_count
            record_count=$(count_records_today "$collector")
            _pass "${collector} data is fresh (${record_count} records today)"
        else
            local data_file="${DATA_DIR}/metrics/${collector}_$(date '+%Y-%m-%d').tsv"
            if [[ -f "$data_file" ]]; then
                _warn "${collector} data is STALE (older than ${max_age} min)" "cron may be broken"
            else
                _warn "${collector} has NO data for today" "collector may not have run yet"
            fi
        fi
    done
}

# =============================================================
# CHECK 3: Log and data directories are writable
# =============================================================
check_directories() {
    echo ""
    echo "[ Directory Permissions ]"

    for dir in "$LOG_DIR" "$DATA_DIR" "${DATA_DIR}/metrics" "${DATA_DIR}/alerts" "${DATA_DIR}/reports"; do
        if [[ -d "$dir" && -w "$dir" ]]; then
            _pass "${dir} — writable"
        elif [[ ! -d "$dir" ]]; then
            _fail "${dir} — directory does not exist"
        else
            _fail "${dir} — NOT writable (check permissions)"
        fi
    done
}

# =============================================================
# CHECK 4: Available disk space for log and data directories
# =============================================================
check_disk_space() {
    echo ""
    echo "[ Disk Space for Monitoring Directories ]"

    local min_free_mb="${MIN_FREE_DISK_MB:-500}"

    for dir in "$LOG_DIR" "$DATA_DIR"; do
        if [[ ! -d "$dir" ]]; then
            _warn "Skipping disk check for non-existent: ${dir}"
            continue
        fi

        # df -m shows disk usage in megabytes
        # awk gets the 4th column (available MB) for the given path
        local free_mb
        free_mb=$(df -m "$dir" | awk 'NR==2 { print $4 }')

        if (( free_mb >= min_free_mb )); then
            _pass "${dir} — ${free_mb}MB free (min required: ${min_free_mb}MB)"
        else
            _fail "${dir} — only ${free_mb}MB free! Need at least ${min_free_mb}MB"
        fi
    done
}

# =============================================================
# CHECK 5: Cron job is installed
# =============================================================
check_cron() {
    echo ""
    echo "[ Cron Jobs ]"

    # Check if any monitoring cron jobs exist for current user
    local cron_output
    cron_output=$(crontab -l 2>/dev/null)

    if echo "$cron_output" | grep -q "monitor\|alert-check\|report" 2>/dev/null; then
        local job_count
        job_count=$(echo "$cron_output" | grep -c "monitor\|alert-check\|report")
        _pass "Cron jobs installed (${job_count} monitoring jobs found)"
    else
        _warn "No monitoring cron jobs found" "run: bash cron/install-cron.sh"
    fi
}

# =============================================================
# CHECK 6: Alert scripts exist and are executable
# =============================================================
check_alert_scripts() {
    echo ""
    echo "[ Alert Scripts ]"
    local scripts=(checker.sh dispatcher.sh dedup.sh trend_detector.sh health_score.sh)

    for script_name in "${scripts[@]}"; do
        local script="${ALERTS_DIR}/${script_name}"
        if [[ -f "$script" && -x "$script" ]]; then
            _pass "${script_name}"
        elif [[ -f "$script" ]]; then
            _warn "${script_name} not executable" "run: chmod +x ${script}"
        else
            _fail "${script_name} missing"
        fi
    done
}

# =============================================================
# CHECK 7: Required config files exist and have content
# =============================================================
check_config() {
    echo ""
    echo "[ Configuration Files ]"
    local config_files=(thresholds.conf notifications.conf services.conf)

    for conf in "${config_files[@]}"; do
        local conf_path="${PROJECT_ROOT}/config/${conf}"
        if [[ -f "$conf_path" && -s "$conf_path" ]]; then
            _pass "config/${conf}"
        elif [[ -f "$conf_path" ]]; then
            _warn "config/${conf} exists but is empty"
        else
            _fail "config/${conf} missing" "copy from .env.example and customize"
        fi
    done
}

# =============================================================
# MAIN — Run all checks and print summary
# =============================================================
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║        MONITORING SUITE — SELF TEST              ║"
    echo "║  $(date '+%Y-%m-%d %H:%M:%S')                          ║"
    echo "╚══════════════════════════════════════════════════╝"

    check_collectors
    check_data_freshness
    check_directories
    check_disk_space
    check_cron
    check_alert_scripts
    check_config

    # Summary
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Results: $(( _PASS )) passed  |  $(( _WARN )) warnings  |  $(( _FAIL )) failed"
    echo "══════════════════════════════════════════════════"

    if (( _FAIL > 0 )); then
        echo -e "\033[0;31m  Status: UNHEALTHY — ${_FAIL} critical issue(s) need attention\033[0m"
        log_error "Self-test FAILED: ${_FAIL} failures, ${_WARN} warnings"
        exit 1
    elif (( _WARN > 0 )); then
        echo -e "\033[0;33m  Status: DEGRADED — ${_WARN} warning(s) to review\033[0m"
        log_warn "Self-test DEGRADED: ${_WARN} warnings"
        exit 0
    else
        echo -e "\033[0;32m  Status: HEALTHY — All checks passed\033[0m"
        log_info "Self-test PASSED: All ${_PASS} checks healthy"
        exit 0
    fi
}

main "$@"
