#!/usr/bin/env bash
# .ops-core/lib/logger.sh — Structured, prefix-aware logger for the orchestrator.
# Designed to coexist with .scripts/logger.sh (no name collisions — uses ops_ prefix).
#
# Features:
#   - Colored output locally; plain text in CI or OPS_PLAIN=true
#   - Optional [service] prefix for log multiplexing (Phase 5)
#   - All output routed through a single _ops_log_line() so CI stripping is centralized
#
# Usage: source .ops-core/lib/logger.sh (after init.sh)

# Guard against double-sourcing
if [[ "${_OPS_CORE_LOGGER_LOADED:-}" == "1" ]]; then
  return 0
fi
_OPS_CORE_LOGGER_LOADED=1

# Inherit colors from init.sh (already exported). Provide safe fallbacks.
: "${OPS_RED:=$'\033[0;31m'}"
: "${OPS_GREEN:=$'\033[0;32m'}"
: "${OPS_YELLOW:=$'\033[1;33m'}"
: "${OPS_BLUE:=$'\033[0;34m'}"
: "${OPS_CYAN:=$'\033[0;36m'}"
: "${OPS_MAGENTA:=$'\033[0;35m'}"
: "${OPS_BOLD:=$'\033[1m'}"
: "${OPS_DIM:=$'\033[2m'}"
: "${OPS_NC:=$'\033[0m'}"

# ============================================================================
# OPTIONAL SERVICE PREFIX (for log multiplexing in Phase 5)
# Set OPS_LOG_SERVICE=<name> before running a service action.
# ============================================================================
OPS_LOG_SERVICE="${OPS_LOG_SERVICE:-}"

# Service-tag colors — rotate through a small palette indexed by service name hash.
# Currently returns CYAN; Phase 5 will implement the full palette.
_ops_service_color() {
  printf '%s' "${OPS_CYAN}"
}

# ============================================================================
# CORE RENDERING
# ============================================================================

# Internal: render and emit one log line.
# Args: level  color  message  [stream: stdout|stderr]
_ops_log_line() {
  local level="$1"
  local color="$2"
  local msg="$3"
  local stream="${4:-stdout}"

  local timestamp
  timestamp="$(date "+%H:%M:%S")"

  local service_tag=""
  if [[ -n "${OPS_LOG_SERVICE}" ]]; then
    if [[ "${OPS_PLAIN}" == "true" ]]; then
      service_tag="[${OPS_LOG_SERVICE}] "
    else
      service_tag="$(_ops_service_color)[${OPS_LOG_SERVICE}]${OPS_NC} "
    fi
  fi

  local formatted
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    # CI / plain: no ANSI sequences, ISO timestamp, structured level field
    formatted="$(date -u "+%Y-%m-%dT%H:%M:%SZ") [${level}] ${service_tag}${msg}"
  else
    formatted="${OPS_DIM}[${timestamp}]${OPS_NC} ${color}[${level}]${OPS_NC} ${service_tag}${msg}"
  fi

  if [[ "${stream}" == "stderr" ]]; then
    printf '%s\n' "${formatted}" >&2
  else
    printf '%s\n' "${formatted}"
  fi
}

# Streams stdin and prefixes each line. Optimized for speed.
_ops_log_stream() {
  local service_tag=""
  if [[ -n "${OPS_LOG_SERVICE:-}" ]]; then
    if [[ "${OPS_PLAIN}" == "true" ]]; then
      service_tag="[${OPS_LOG_SERVICE}] "
    else
      service_tag="$(_ops_service_color)[${OPS_LOG_SERVICE}]${OPS_NC} "
    fi
  fi

  if [[ "${OPS_PLAIN}" == "true" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      printf '%s [STREAM] %s%s\n' "$(date -u "+%Y-%m-%dT%H:%M:%SZ")" "${service_tag}" "${line}"
    done
  else
    while IFS= read -r line || [[ -n "$line" ]]; do
      local ts
      # Use fast bash builtin for timestamp
      printf -v ts '%(%H:%M:%S)T' -1 2>/dev/null || ts="$(date +%H:%M:%S)"
      printf '%s[%s]%s %s[STREAM]%s %s%s\n' "${OPS_DIM}" "${ts}" "${OPS_NC}" "${OPS_DIM}" "${OPS_NC}" "${service_tag}" "${line}"
    done
  fi
}

# ============================================================================
# PUBLIC LOG FUNCTIONS
# ============================================================================

ops_info()    { _ops_log_line "INFO"    "${OPS_BLUE}"    "$*" stdout; }
ops_ok()      { _ops_log_line "OK"      "${OPS_GREEN}"   "$*" stdout; }
ops_warn()    { _ops_log_line "WARN"    "${OPS_YELLOW}"  "$*" stderr; }
ops_error()   { _ops_log_line "ERROR"   "${OPS_RED}"     "$*" stderr; }
ops_debug()   {
  [[ "${OPS_DEBUG:-false}" != "true" ]] && return 0
  _ops_log_line "DEBUG" "${OPS_DIM}" "$*" stderr
}

# Section header — visually groups related output
ops_section() {
  local title="$*"
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    printf '=== %s ===\n' "${title}"
  else
    printf '\n%s%s=== %s ===%s\n\n' "${OPS_BOLD}" "${OPS_BLUE}" "${title}" "${OPS_NC}"
  fi
}

# Inline step indicator (for wizard-style flows)
ops_step() {
  local n="${1}"; local total="${2}"; local msg="${3:-}"
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    printf '[%s/%s] %s\n' "${n}" "${total}" "${msg}"
  else
    printf '%s[%s/%s]%s %s\n' "${OPS_BOLD}" "${n}" "${total}" "${OPS_NC}" "${msg}"
  fi
}
