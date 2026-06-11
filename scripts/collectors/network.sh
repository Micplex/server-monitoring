#!/usr/bin/env bash
# =============================================================
# network.sh — Network Connectivity & Interface Collector
# =============================================================
# WHY: Network issues are often the first symptom of problems.
#      Packet loss, high latency, and port failures all impact
#      users before CPU or memory alarms fire. We probe both
#      from the inside (interface stats) and outside (ping tests).
#
# WHAT WE COLLECT:
#   Part 1 — Interface Statistics (from /proc/net/dev)
#     - RX/TX bytes (throughput)
#     - Packet drops and errors (quality indicators)
#   Part 2 — Connectivity Probes (ping + port checks)
#     - Latency to configured targets
#     - Packet loss percentage
#   Part 3 — Open Port Checks
#     - Verify configured ports are listening
#
# TSV FILES WRITTEN:
#   network_iface_YYYY-MM-DD.tsv  — Interface stats
#   network_probe_YYYY-MM-DD.tsv  — Ping/latency results
#   network_ports_YYYY-MM-DD.tsv  — Port status
# =============================================================

SCRIPT_NAME="network.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
source "${CORE_DIR}/config_loader.sh"
source "${CORE_DIR}/logger.sh"
source "${CORE_DIR}/metrics_writer.sh"
source "${CORE_DIR}/lock_manager.sh"

acquire_lock "collector_network" || exit 0
log_start

# =============================================================
# FUNCTION: Collect network interface statistics
# =============================================================
# /proc/net/dev format (after 2 header lines):
#   iface: rx_bytes rx_pkts rx_errs rx_drop ... tx_bytes tx_pkts tx_errs tx_drop ...
collect_interface_stats() {
    log_info "Collecting interface statistics"

    # Skip header lines (first 2), skip loopback (lo)
    grep -v "Inter-\|face\|lo:" /proc/net/dev | while read -r line; do
        # Remove trailing colon from interface name
        local iface
        iface=$(echo "$line" | awk '{gsub(/:/, "", $1); print $1}')
        [[ -z "$iface" ]] && continue

        # Parse /proc/net/dev columns:
        # $2=rx_bytes $3=rx_pkts $4=rx_errs $5=rx_drop
        # $10=tx_bytes $11=tx_pkts $12=tx_errs $13=tx_drop
        local rx_bytes rx_packets rx_errors rx_drops
        local tx_bytes tx_packets tx_errors tx_drops
        read -r _ rx_bytes rx_packets rx_errors rx_drops _ _ _ _ \
                  tx_bytes tx_packets tx_errors tx_drops <<< "$line"

        # Convert bytes to MB for readability
        local rx_mb tx_mb
        rx_mb=$(awk -v b="$rx_bytes" 'BEGIN { printf "%.1f", b/1024/1024 }')
        tx_mb=$(awk -v b="$tx_bytes" 'BEGIN { printf "%.1f", b/1024/1024 }')

        log_info "Interface [${iface}]: RX=${rx_mb}MB TX=${tx_mb}MB | Errors: ${rx_errors}rx/${tx_errors}tx | Drops: ${rx_drops}rx/${tx_drops}tx"

        # Alert on packet errors (non-zero errors = hardware or driver issue)
        if (( rx_errors > 0 || tx_errors > 0 )); then
            log_warn "Interface [${iface}] has errors: ${rx_errors} rx_errors, ${tx_errors} tx_errors"
        fi

        # Alert on packet drops (drops = kernel buffer overflow, usually high load)
        local drop_threshold="${PACKET_DROP_THRESHOLD:-100}"
        if (( rx_drops > drop_threshold || tx_drops > drop_threshold )); then
            log_warn "Interface [${iface}] has high drops: ${rx_drops} rx_drop, ${tx_drops} tx_drop"
        fi

        write_metric "network_iface" \
            "$iface" \
            "$rx_bytes" "$rx_mb" "$rx_packets" "$rx_errors" "$rx_drops" \
            "$tx_bytes" "$tx_mb" "$tx_packets" "$tx_errors" "$tx_drops"
    done
}

# =============================================================
# FUNCTION: Ping a host and measure latency + packet loss
# =============================================================
# Returns: "latency_ms packet_loss_pct status"
probe_host() {
    local target="$1"
    local count="${PING_COUNT:-4}"
    local timeout="${PING_TIMEOUT:-5}"

    # -c = packet count, -W = timeout per packet
    local ping_output
    ping_output=$(ping -c "$count" -W "$timeout" "$target" 2>&1)
    local ping_exit=$?

    if (( ping_exit != 0 )); then
        # Host unreachable or timeout
        echo "0 100 unreachable"
        return 1
    fi

    # Parse average latency from: "rtt min/avg/max/mdev = 0.234/0.456/0.789/0.123 ms"
    local avg_latency
    avg_latency=$(echo "$ping_output" | grep -oP 'rtt.*= \K[\d.]+/\K[\d.]+' || echo "0")

    # Parse packet loss: "4 packets transmitted, 3 received, 25% packet loss"
    local packet_loss
    packet_loss=$(echo "$ping_output" | grep -oP '\d+(?=% packet loss)' || echo "0")

    echo "$avg_latency $packet_loss reachable"
}

# =============================================================
# FUNCTION: Check if a TCP port is listening
# =============================================================
# ss (socket statistics) is the modern replacement for netstat
# WHY: netstat is deprecated on modern Linux systems
check_port() {
    local host="$1"
    local port="$2"

    # Use nc (netcat) for port checking — works for remote hosts too
    # -z = scan mode (no data sent), -w = timeout in seconds
    if nc -z -w 3 "$host" "$port" 2>/dev/null; then
        echo "open"
    else
        echo "closed"
    fi
}

# =============================================================
# FUNCTION: Run all connectivity probes
# =============================================================
run_probes() {
    log_info "Running connectivity probes"

    # PING_TARGETS from config/notifications.conf or thresholds.conf
    # Default: just ping the gateway and a public DNS server
    local ping_targets="${PING_TARGETS:-8.8.8.8 1.1.1.1}"
    local latency_warn="${PING_LATENCY_WARNING:-200}"
    local loss_warn="${PING_LOSS_WARNING:-10}"

    for target in $ping_targets; do
        local result
        result="$(probe_host "$target")"
        read -r latency loss status <<< "$result"

        log_info "Ping [${target}]: ${latency}ms latency, ${loss}% loss — ${status}"

        # Alert on high latency
        local latency_int
        latency_int=$(printf "%.0f" "${latency:-0}")
        if (( latency_int > latency_warn )); then
            log_warn "High latency to ${target}: ${latency}ms (threshold: ${latency_warn}ms)"
        fi

        # Alert on packet loss
        if (( ${loss:-0} >= ${loss_warn:-10} )); then
            log_warn "Packet loss to ${target}: ${loss}% (threshold: ${loss_warn}%)"
        fi

        write_metric "network_probe" \
            "$target" \
            "$latency" \
            "$loss" \
            "$status"
    done
}

# =============================================================
# FUNCTION: Check configured TCP ports
# =============================================================
check_ports() {
    log_info "Checking TCP port status"

    # CHECK_PORTS format: "host:port host:port ..."
    # Example: CHECK_PORTS="localhost:22 localhost:80 db-server:5432"
    local port_targets="${CHECK_PORTS:-localhost:22}"

    for target in $port_targets; do
        local host port
        host=$(echo "$target" | cut -d: -f1)
        port=$(echo "$target" | cut -d: -f2)

        local port_status
        port_status="$(check_port "$host" "$port")"
        log_info "Port [${host}:${port}]: ${port_status}"

        if [[ "$port_status" == "closed" ]]; then
            log_warn "Port ${host}:${port} is CLOSED — service may be down"
        fi

        write_metric "network_ports" \
            "$host" \
            "$port" \
            "$port_status"
    done
}

main() {
    collect_interface_stats
    run_probes
    check_ports
    log_end 0
}

main "$@"
