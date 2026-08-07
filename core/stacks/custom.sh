#!/usr/bin/env bash
# .ops-core/stacks/custom.sh — Custom (user-defined) stack strategy stub.
# When stack=custom, a configured action command is executed in an isolated shell.

set -euo pipefail

_CUSTOM_STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/command_exec.sh
source "${_CUSTOM_STACK_DIR}/../lib/command_exec.sh"

custom_dispatch() {
  local action="${1:-}"
  local explicit_cmd="${2:-}"

  if [[ -n "${explicit_cmd}" && "${explicit_cmd}" != "null" ]]; then
    ops_run_configured_command "${explicit_cmd}"
    return $?
  fi

  case "${action}" in
    stop)
      local pid_file="${OPS_PROJECT_RUN_DIR:-${OPS_PROJECT_ROOT}/.ops.project/run}/${OPS_SERVICE_ID}.pid"
      if [[ -f "${pid_file}" ]]; then
        local pid
        pid="$(cat "${pid_file}")"
        if kill -0 "${pid}" 2>/dev/null; then
          kill "${pid}" || true
        fi
        rm -f "${pid_file}"
      fi
      return 0
      ;;
    status)
      local pid_file="${OPS_PROJECT_RUN_DIR:-${OPS_PROJECT_ROOT}/.ops.project/run}/${OPS_SERVICE_ID}.pid"
      if [[ -f "${pid_file}" ]]; then
        local pid
        pid="$(cat "${pid_file}")"
        if kill -0 "${pid}" 2>/dev/null; then
          return 0 # Running
        fi
        # Stale pid
        rm -f "${pid_file}"
      fi
      return 1 # Not running
      ;;
  esac

  return 10
}
