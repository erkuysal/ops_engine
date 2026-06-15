#!/usr/bin/env bash
# .ops-core/lib/init.sh — Shared bootstrap for all ops-core scripts.
# Source this file first in every .ops-core script.
# Provides: strict mode, path resolvers, error helpers, lockfile, color constants.

set -euo pipefail

# ============================================================================
# GUARD: prevent double-sourcing
# ============================================================================
if [[ "${_OPS_CORE_INIT_LOADED:-}" == "1" ]]; then
  return 0
fi
_OPS_CORE_INIT_LOADED=1

# ============================================================================
# COLORS — compatible with existing common.sh palette; safe to coexist
# ============================================================================
if [[ -z "${_OPS_COLORS_LOADED:-}" ]]; then
  OPS_RED=$'\033[0;31m'
  OPS_GREEN=$'\033[0;32m'
  OPS_YELLOW=$'\033[1;33m'
  OPS_BLUE=$'\033[0;34m'
  OPS_CYAN=$'\033[0;36m'
  OPS_MAGENTA=$'\033[0;35m'
  OPS_BOLD=$'\033[1m'
  OPS_DIM=$'\033[2m'
  OPS_NC=$'\033[0m'
  export OPS_RED OPS_GREEN OPS_YELLOW OPS_BLUE OPS_CYAN OPS_MAGENTA OPS_BOLD OPS_DIM OPS_NC
  _OPS_COLORS_LOADED=1
fi

# ============================================================================
# CI DETECTION
# ============================================================================
OPS_CI=${CI:-false}
# Normalize: treat any non-empty truthy string as CI
[[ "${OPS_CI}" == "true" || "${OPS_CI}" == "1" ]] && OPS_CI=true || OPS_CI=false
export OPS_CI

# Plain mode: no color output when CI or --plain was requested
OPS_PLAIN=${OPS_PLAIN:-${OPS_CI}}
export OPS_PLAIN

# Debug/trace mode
OPS_DEBUG=${OPS_DEBUG:-false}
export OPS_DEBUG

# ============================================================================
# PATH RESOLVERS
# ============================================================================

# Return the absolute path to the project root (directory containing ops.sh).
# Detection: walk up from the caller's dir until we find ops.sh or .ops/core/.
repo_root() {
  local dir
  # Prefer OPS_PROJECT_ROOT if already resolved by ops.sh
  if [[ -n "${OPS_PROJECT_ROOT:-}" ]]; then
    printf '%s' "${OPS_PROJECT_ROOT}"
    return 0
  fi
  # Walk up from this file's location (.ops/core/lib/ → .ops/core/ → project root)
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  if [[ -f "${dir}/ops.sh" || -d "${dir}/.ops/core" ]]; then
    printf '%s' "${dir}"
    return 0
  fi
  # Last resort: walk up from cwd
  dir="$(pwd -P)"
  while [[ -n "${dir}" && "${dir}" != "/" ]]; do
    if [[ -f "${dir}/ops.sh" ]]; then
      printf '%s' "${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  die "Could not determine project root. Run ops from within the project directory."
}

# Return the absolute path to .ops/core/
ops_core_root() {
  if [[ -n "${OPS_CORE_ROOT:-}" ]]; then
    printf '%s' "${OPS_CORE_ROOT}"
  else
    printf '%s/.ops/core' "$(repo_root)"
  fi
}

# Return the absolute path to .ops.yaml
manifest_path() {
  printf '%s/.ops.yaml' "$(repo_root)"
}

# Return the absolute path to .ops/ (package checkout and optional project-local overrides)
ops_local_dir() {
  printf '%s/.ops' "$(repo_root)"
}

# ============================================================================
# ENVIRONMENT BOOTSTRAP — resolve and export OPS_PROJECT_ROOT once
# ============================================================================
_ops_bootstrap_root() {
  if [[ -z "${OPS_PROJECT_ROOT:-}" ]]; then
    OPS_PROJECT_ROOT="$(repo_root)"
    export OPS_PROJECT_ROOT
  fi
  OPS_CORE_ROOT="${OPS_CORE_ROOT:-${OPS_PROJECT_ROOT}/.ops/core}"
  OPS_LOCAL_DIR="${OPS_PROJECT_ROOT}/.ops"
  OPS_MANIFEST="${OPS_PROJECT_ROOT}/.ops.yaml"
  OPS_PROJECT_STATE_DIR="${OPS_PROJECT_STATE_DIR:-${OPS_PROJECT_ROOT}/.ops.project}"
  OPS_PROJECT_LOG_DIR="${OPS_PROJECT_LOG_DIR:-${OPS_PROJECT_STATE_DIR}/logs}"
  OPS_PROJECT_RUN_DIR="${OPS_PROJECT_RUN_DIR:-${OPS_PROJECT_STATE_DIR}/run}"
  OPS_PROJECT_GENERATED_DIR="${OPS_PROJECT_GENERATED_DIR:-${OPS_PROJECT_STATE_DIR}/generated}"
  OPS_PROJECT_CONFIG_DIR="${OPS_PROJECT_CONFIG_DIR:-${OPS_PROJECT_STATE_DIR}/config}"
  OPS_PROJECT_HISTORY_DIR="${OPS_PROJECT_HISTORY_DIR:-${OPS_PROJECT_STATE_DIR}/.history}"
  OPS_PROFILES_DIR="${OPS_PROFILES_DIR:-${OPS_PROJECT_STATE_DIR}/profiles}"
  export OPS_CORE_ROOT OPS_LOCAL_DIR OPS_MANIFEST
  export OPS_PROJECT_STATE_DIR OPS_PROJECT_LOG_DIR OPS_PROJECT_RUN_DIR OPS_PROJECT_GENERATED_DIR OPS_PROJECT_CONFIG_DIR OPS_PROJECT_HISTORY_DIR OPS_PROFILES_DIR
}
_ops_bootstrap_root

# Ensure generated project bin directory exists and is on PATH (for cross-shell shims).
# Shims are machine-local runtime artifacts, so they belong in .ops.project rather than
# the package checkout under .ops/.
OPS_PROJECT_BIN="${OPS_PROJECT_BIN:-${OPS_PROJECT_ROOT}/.ops.project/generated/bin/shims}"
if [[ ":${PATH}:" != *":${OPS_PROJECT_BIN}:"* ]]; then
  PATH="${OPS_PROJECT_BIN}:${PATH}"
  export PATH
fi

# ============================================================================
# ERROR HELPERS
# ============================================================================

# Print a formatted message to stderr and exit 1.
# Usage: die "message" [exit_code]
die() {
  local msg="${1:-fatal error}"
  local code="${2:-1}"
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    printf '[ERROR] %s\n' "${msg}" >&2
  else
    printf '%s[ERROR]%s %s\n' "${OPS_RED}" "${OPS_NC}" "${msg}" >&2
  fi
  exit "${code}"
}

# Print a warning to stderr (does not exit).
warn() {
  local msg="${1:-}"
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    printf '[WARN] %s\n' "${msg}" >&2
  else
    printf '%s[WARN]%s %s\n' "${OPS_YELLOW}" "${OPS_NC}" "${msg}" >&2
  fi
}

# Print an informational message to stdout.
info() {
  local msg="${1:-}"
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    printf '[INFO] %s\n' "${msg}"
  else
    printf '%s[INFO]%s %s\n' "${OPS_BLUE}" "${OPS_NC}" "${msg}"
  fi
}

# Print a success message to stdout.
ok() {
  local msg="${1:-}"
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    printf '[OK] %s\n' "${msg}"
  else
    printf '%s[OK]%s %s\n' "${OPS_GREEN}" "${OPS_NC}" "${msg}"
  fi
}

# Print a debug trace — only when OPS_DEBUG=true.
debug() {
  [[ "${OPS_DEBUG}" != "true" ]] && return 0
  local msg="${1:-}"
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    printf '[DEBUG] %s\n' "${msg}" >&2
  else
    printf '%s[DEBUG]%s %s\n' "${OPS_DIM}" "${OPS_NC}" "${msg}" >&2
  fi
}

# ============================================================================
# LOCKFILE HELPER — prevent concurrent mutating commands (init, update)
# ============================================================================
OPS_LOCK_FILE="${OPS_LOCK_FILE:-${OPS_PROJECT_RUN_DIR}/ops.lock}"

# Acquire the ops lock. Call at the start of any mutating command.
# Usage: ops_lock_acquire "command-name"
ops_lock_acquire() {
  local cmd="${1:-ops}"
  local lock_dir
  lock_dir="$(dirname "${OPS_LOCK_FILE}")"
  mkdir -p "${lock_dir}"

  if [[ -f "${OPS_LOCK_FILE}" ]]; then
    local holder
    holder="$(cat "${OPS_LOCK_FILE}" 2>/dev/null || echo "unknown")"
    die "Another ops operation is in progress (${holder}). If stale, remove: ${OPS_LOCK_FILE}"
  fi

  printf '%s (pid %s)\n' "${cmd}" "$$" > "${OPS_LOCK_FILE}"
  debug "Lock acquired by '${cmd}' (pid $$)"
}

# Release the ops lock. Call at exit (via trap) in any mutating command.
ops_lock_release() {
  [[ -f "${OPS_LOCK_FILE}" ]] && rm -f "${OPS_LOCK_FILE}" && debug "Lock released"
}

# ============================================================================
# SAFETY CHECKS
# ============================================================================

# Verify that a path stays within the project root (no traversal).
# Usage: require_within_root "/abs/path/to/check"
require_within_root() {
  local target
  target="$(cd "${1:?require_within_root: path required}" && pwd 2>/dev/null)" || \
    die "Path does not exist: $1"
  case "${target}" in
    "${OPS_PROJECT_ROOT}"*) : ;; # OK
    *) die "Path traversal denied: '${target}' is outside project root '${OPS_PROJECT_ROOT}'" ;;
  esac
}

# Check that required external binaries are available.
# Usage: require_bins yq jq curl
require_bins() {
  local missing=()
  local bin
  for bin in "$@"; do
    command -v "${bin}" &>/dev/null || missing+=("${bin}")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}. Install them and retry."
  fi
}

# ============================================================================
# MISC UTILITIES
# ============================================================================

# Ensure a directory exists; create it (incl. parents) if not.
ensure_dir() {
  local dir="${1:?ensure_dir: path required}"
  [[ -d "${dir}" ]] || mkdir -p "${dir}"
}

# Print the current timestamp in ISO-8601 format (UTC).
ops_timestamp() {
  date -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date "+%Y-%m-%dT%H:%M:%SZ"
}
