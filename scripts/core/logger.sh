#!/usr/bin/env bash
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_DIR="${LOG_DIR:-$(dirname "$0")/../../logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/monitoring.log"
_log(){ local lvl="$1"; shift; echo "$(date '+%Y-%m-%d %H:%M:%S') [$lvl] $*" | tee -a "$LOG_FILE"; }
log_debug(){ [[ "$LOG_LEVEL" == "DEBUG" ]] && _log DEBUG "$@"; }
log_info(){  _log INFO  "$@"; }
log_warn(){  _log WARN  "$@"; }
log_error(){ _log ERROR "$@"; }
