#!/usr/bin/env bash

probe_go_stack_id() {
  printf 'go'
}

probe_go_score_dir() {
  local dir="$1"
  local score=0
  [[ -f "${dir}/go.mod" ]] && score=$((score + 3))
  [[ -f "${dir}/go.sum" ]] && score=$((score + 1))
  [[ -f "${dir}/main.go" ]] && score=$((score + 1))
  printf '%d' "${score}"
}
