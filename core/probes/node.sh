#!/usr/bin/env bash

probe_node_stack_id() {
  printf 'node'
}

probe_node_score_dir() {
  local dir="$1"
  local score=0
  [[ -f "${dir}/package.json" ]] && score=$((score + 3))
  [[ -f "${dir}/yarn.lock" ]] && score=$((score + 1))
  [[ -f "${dir}/pnpm-lock.yaml" ]] && score=$((score + 1))
  [[ -f "${dir}/package-lock.json" ]] && score=$((score + 1))
  [[ -d "${dir}/node_modules" ]] && score=$((score + 1))
  printf '%d' "${score}"
}
