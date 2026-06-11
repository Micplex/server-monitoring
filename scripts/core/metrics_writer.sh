#!/usr/bin/env bash
write_metric(){
  local collection="$1" && shift
  local dir="${DATA_DIR}/metrics" && mkdir -p "$dir"
  local file="${dir}/${collection}_$(date '+%Y-%m-%d').tsv"
  printf "%s\t%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$file"
}
