#!/usr/bin/env bash

probe_elixir_phoenix_stack_id() {
  printf 'elixir-phoenix'
}

probe_elixir_phoenix_score_dir() {
  local dir="$1"
  local score=0
  [[ -f "${dir}/mix.exs" ]] && score=$((score + 3))
  [[ -f "${dir}/config/config.exs" ]] && score=$((score + 2))
  [[ -f "${dir}/config/runtime.exs" ]] && score=$((score + 1))
  if [[ -d "${dir}/lib" ]]; then
    local web_count
    web_count="$(find "${dir}/lib" -maxdepth 1 -type d -name '*_web' 2>/dev/null | wc -l)"
    [[ "${web_count}" -gt 0 ]] && score=$((score + 2))
  fi
  printf '%d' "${score}"
}
