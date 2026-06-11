#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="${PROJECT_ROOT}/data"
LOG_DIR="${PROJECT_ROOT}/logs"
CONF_DIR="${PROJECT_ROOT}/config"
for f in "$CONF_DIR"/*.conf; do [[ -f "$f" ]] && source "$f"; done
export DATA_DIR LOG_DIR PROJECT_ROOT CONF_DIR
