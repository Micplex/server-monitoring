#!/usr/bin/env bash
get_latest_value(){
  local collection="$1" col="${2:-2}"
  local f="${DATA_DIR}/metrics/${collection}_$(date '+%Y-%m-%d').tsv"
  [[ -f "$f" ]] && tail -1 "$f" | awk -F'\t' -v c="$col" '{print $c}'
}
get_avg(){
  local collection="$1" col="${2:-2}" n="${3:-12}"
  local f="${DATA_DIR}/metrics/${collection}_$(date '+%Y-%m-%d').tsv"
  [[ -f "$f" ]] && tail -n "$n" "$f" | awk -F'\t' -v c="$col" '{s+=$c;n++}END{if(n)printf "%.1f",s/n}'
}
