#!/usr/bin/env bash
# .ops-core/lib/preflight.sh — Pre-execution binary checks.
#
# Requires: logger.sh (sourced first)

set -euo pipefail
if [[ "${_OPS_CORE_PREFLIGHT_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_PREFLIGHT_LOADED=1

# Load cross-shell helpers (optional)
if [[ -f "${OPS_CORE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/cross_shell.sh" ]]; then
  # shellcheck source=/dev/null
  source "${OPS_CORE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/cross_shell.sh"
fi

# Check required binaries for a specific stack.
# Exits with code 3 if a requirement is missing.
preflight_check_stack() {
  local stack="${1:?preflight_check_stack: stack required}"

  local reqs=()
  case "${stack}" in
    django)
      reqs=("python|python3")
      ;;
    node)
      reqs=("node" "npm")
      ;;
    go)
      reqs=("go")
      ;;
    elixir-phoenix)
      reqs=("elixir" "mix")
      ;;
    docker)
      reqs=("docker")
      ;;
    custom)
      # No predefined requirements
      ;;
  esac

  local missing=()
  local b
  for b in "${reqs[@]+"${reqs[@]}"}"; do
    if [[ "${b}" == *"|"* ]]; then
      # Handle alternatives like "python|python3"
      local alt_found=false
      local alt
      IFS='|' read -ra alts <<< "${b}"
      for alt in "${alts[@]}"; do
        if command -v "${alt}" >/dev/null 2>&1; then
          alt_found=true
          break
        fi
      done
      if [[ "${alt_found}" == "false" ]]; then
        # If running under WSL, try to probe Windows for the binary and create shim
        local primary_alt
        primary_alt="${alts[0]}"
        if type ensure_cross_shell_bin >/dev/null 2>&1 && ensure_cross_shell_bin "${primary_alt}"; then
          : # shim created, binary now available
        else
          missing+=("${b}")
        fi
      fi
    else
      if ! command -v "${b}" >/dev/null 2>&1; then
        # Try cross-shell shim (WSL -> Windows) before reporting missing
        if type ensure_cross_shell_bin >/dev/null 2>&1 && ensure_cross_shell_bin "${b}"; then
          :
        else
          missing+=("${b}")
        fi
      fi
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    ops_error "Preflight failed: missing required binaries for stack '${stack}': ${missing[*]}"
    exit 3
  fi

  return 0
}
