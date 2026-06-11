#!/usr/bin/env bash
# =============================================================
# ssh_remote.sh — SSH wrapper for multi-host monitoring
# =============================================================
# WHY: Enterprise deployments monitor dozens of servers from one
#      central machine. This wrapper standardizes SSH connections,
#      handles timeouts gracefully, and aggregates results so that
#      all collector scripts work on remote hosts just like local.
#
# REMOTE HOST CONFIG: config/hosts.conf
#   Format: alias|hostname_or_ip|ssh_user|ssh_key_path|ssh_port
#   Example:
#     web-01|192.168.1.10|monitor|/etc/monitoring/keys/id_rsa|22
#     db-01|192.168.1.11|monitor|/etc/monitoring/keys/id_rsa|22
#
# USAGE:
#   source "$(dirname "$0")/../core/ssh_remote.sh"
#   remote_exec "web-01" "free -m"
#   run_collector_remote "web-01" "memory"
#   run_all_hosts "cpu"
# =============================================================

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f log_info &>/dev/null; then
    source "${CORE_DIR}/logger.sh"
fi
if [[ -z "$PROJECT_ROOT" ]]; then
    source "${CORE_DIR}/config_loader.sh"
fi

SCRIPT_NAME="ssh_remote.sh"

# SSH timeout settings
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-10}"   # Seconds to wait for connection
SSH_COMMAND_TIMEOUT="${SSH_COMMAND_TIMEOUT:-30}"    # Seconds to wait for command

# --- Parse a host entry from hosts.conf ---
# Returns associative array via nameref (bash 4.3+)
# Format: alias|host|user|key_path|port
_parse_host_entry() {
    local entry="$1"
    # Split on | delimiter
    IFS='|' read -r alias host user key_path port <<< "$entry"
    echo "alias=${alias} host=${host} user=${user} key=${key_path} port=${port:-22}"
}

# --- Get all configured remote hosts ---
# Reads REMOTE_HOSTS array from config/hosts.conf
get_remote_hosts() {
    # REMOTE_HOSTS should be set in config/hosts.conf as an array
    # Example: REMOTE_HOSTS=("web-01|192.168.1.10|monitor|/path/key|22")
    if [[ ${#REMOTE_HOSTS[@]} -eq 0 ]]; then
        log_debug "No remote hosts configured in hosts.conf"
        return 0
    fi
    printf '%s\n' "${REMOTE_HOSTS[@]}"
}

# --- Execute a command on a remote host via SSH ---
# Usage: remote_exec "web-01" "df -h"
# Returns the command output; returns 1 on connection failure
remote_exec() {
    local alias="$1"
    local command="$2"

    # Find the host entry matching this alias
    local host_entry=""
    for entry in "${REMOTE_HOSTS[@]:-}"; do
        local entry_alias
        entry_alias=$(echo "$entry" | cut -d'|' -f1)
        if [[ "$entry_alias" == "$alias" ]]; then
            host_entry="$entry"
            break
        fi
    done

    if [[ -z "$host_entry" ]]; then
        log_error "Remote host '${alias}' not found in hosts.conf"
        return 1
    fi

    # Parse the host entry
    local host user key_path port
    IFS='|' read -r _ host user key_path port <<< "$host_entry"
    port="${port:-22}"

    log_debug "SSH to ${user}@${host}:${port} — running: ${command}"

    # Execute via SSH with strict timeouts
    # -o StrictHostKeyChecking=no: avoids interactive prompts in cron
    # -o ConnectTimeout: fail fast if host unreachable
    # -o BatchMode=yes: no password prompts (key auth only)
    # -o ServerAliveInterval: detect hung connections
    local output
    output=$(ssh \
        -o "StrictHostKeyChecking=no" \
        -o "ConnectTimeout=${SSH_CONNECT_TIMEOUT}" \
        -o "BatchMode=yes" \
        -o "ServerAliveInterval=5" \
        -o "ServerAliveCountMax=2" \
        -i "$key_path" \
        -p "$port" \
        "${user}@${host}" \
        "timeout ${SSH_COMMAND_TIMEOUT} ${command}" \
        2>&1)

    local exit_code=$?
    if (( exit_code != 0 )); then
        log_error "SSH command failed on ${alias} (exit ${exit_code}): ${output}"
        return 1
    fi

    echo "$output"
    return 0
}

# --- Run a collector script on a remote host and store results locally ---
# This copies the collector script to the remote host, executes it,
# and saves the output to the local data directory tagged with hostname
# Usage: run_collector_remote "web-01" "cpu"
run_collector_remote() {
    local host_alias="$1"
    local collector_name="$2"
    local collector_script="${PROJECT_ROOT}/scripts/collectors/${collector_name}.sh"

    if [[ ! -f "$collector_script" ]]; then
        log_error "Collector script not found: ${collector_script}"
        return 1
    fi

    log_info "Running remote collector [${collector_name}] on ${host_alias}"

    # Set REMOTE_HOST env var so the collector script can tag its output correctly
    local output
    output=$(remote_exec "$host_alias" "bash -s" < "$collector_script" 2>&1)
    local exit_code=$?

    if (( exit_code == 0 )); then
        # Store output in a host-specific subdirectory
        local host_data_dir="${DATA_DIR}/metrics/remote/${host_alias}"
        mkdir -p "$host_data_dir"
        echo "$output" >> "${host_data_dir}/${collector_name}_$(date '+%Y-%m-%d').tsv"
        log_info "Remote metrics stored for ${host_alias}/${collector_name}"
    else
        log_error "Remote collection failed for ${host_alias}/${collector_name}"
        return 1
    fi
}

# --- Run a collector across all configured remote hosts ---
# Usage: run_all_hosts "cpu"
run_all_hosts() {
    local collector_name="$1"
    local failed=0

    if [[ ${#REMOTE_HOSTS[@]} -eq 0 ]]; then
        log_debug "No remote hosts configured — skipping remote collection"
        return 0
    fi

    log_info "Running [${collector_name}] collector on ${#REMOTE_HOSTS[@]} remote hosts"

    for entry in "${REMOTE_HOSTS[@]}"; do
        local host_alias
        host_alias=$(echo "$entry" | cut -d'|' -f1)
        run_collector_remote "$host_alias" "$collector_name" || ((failed++))
    done

    if (( failed > 0 )); then
        log_warn "${failed} remote host(s) failed during [${collector_name}] collection"
        return 1
    fi

    return 0
}

# --- Ping test for a remote host (reachability check) ---
# Usage: is_host_reachable "web-01"
is_host_reachable() {
    local alias="$1"
    local host_entry=""
    for entry in "${REMOTE_HOSTS[@]:-}"; do
        local entry_alias
        entry_alias=$(echo "$entry" | cut -d'|' -f1)
        if [[ "$entry_alias" == "$alias" ]]; then
            host_entry="$entry"
            break
        fi
    done

    local host
    host=$(echo "$host_entry" | cut -d'|' -f2)
    [[ -z "$host" ]] && return 1

    # Send 1 ping, 2 second timeout
    ping -c 1 -W 2 "$host" &>/dev/null
}
