#!/usr/bin/env bash
LOCK_DIR="/tmp/monitoring_locks"
mkdir -p "$LOCK_DIR"
acquire_lock(){ mkdir "$LOCK_DIR/$1.lock" 2>/dev/null; }
release_lock(){ rmdir "$LOCK_DIR/$1.lock" 2>/dev/null; }
