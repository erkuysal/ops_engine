#!/usr/bin/env bash
# .ops/core/lib/cleanup.sh — Runtime state cleanup helpers.

set -euo pipefail
if [[ "${_OPS_CORE_CLEANUP_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_CLEANUP_LOADED=1

cleanup_pid_is_alive() {
  local pid="${1:-}"
  [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

cleanup_read_pid() {
  local file="${1:?cleanup_read_pid: file required}"
  tr -d '[:space:]' < "${file}" 2>/dev/null || true
}

cleanup_stale_pid_files() {
  local apply="${1:-false}"
  local count=0 file pid rel

  [[ -d "${OPS_PROJECT_RUN_DIR}" ]] || return 0

  while IFS= read -r file; do
    [[ -n "${file}" && -f "${file}" ]] || continue
    pid="$(cleanup_read_pid "${file}")"
    cleanup_pid_is_alive "${pid}" && continue
    rel="${file#${OPS_PROJECT_ROOT}/}"
    if [[ "${apply}" == "true" ]]; then
      rm -f "${file}"
      printf 'removed stale pid: %s\n' "${rel}"
    else
      printf 'stale pid: %s%s\n' "${rel}" "$([[ -n "${pid}" ]] && printf ' (%s)' "${pid}")"
    fi
    count=$((count + 1))
  done < <(find "${OPS_PROJECT_RUN_DIR}" -type f -name '*.pid' 2>/dev/null | sort)

  [[ "${count}" -gt 0 ]] || printf 'none\n'
  return 0
}

cleanup_old_log_files() {
  local apply="${1:-false}" days="${2:-}"
  local count=0 file rel

  [[ -n "${days}" ]] || return 0
  [[ "${days}" =~ ^[0-9]+$ ]] || die "--logs-older-than requires a day count" 2
  [[ -d "${OPS_PROJECT_LOG_DIR}" ]] || return 0

  while IFS= read -r file; do
    [[ -n "${file}" && -f "${file}" ]] || continue
    rel="${file#${OPS_PROJECT_ROOT}/}"
    if [[ "${apply}" == "true" ]]; then
      rm -f "${file}"
      printf 'removed old log: %s\n' "${rel}"
    else
      printf 'old log: %s\n' "${rel}"
    fi
    count=$((count + 1))
  done < <(find "${OPS_PROJECT_LOG_DIR}" -type f -name '*.log' -mtime +"${days}" 2>/dev/null | sort)

  [[ "${count}" -gt 0 ]] || printf 'none\n'
  return 0
}

return 0
