#!/usr/bin/env bash
# .ops-core/stacks/node.sh — Node.js stack strategy.

set -euo pipefail

_NODE_STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/init.sh
source "${_NODE_STACK_DIR}/../lib/init.sh"
# shellcheck source=../lib/cross_shell.sh
source "${_NODE_STACK_DIR}/../lib/cross_shell.sh"
# shellcheck source=../lib/command_exec.sh
source "${_NODE_STACK_DIR}/../lib/command_exec.sh"

node_dispatch() {
  local action="${1:-}"
  local explicit_cmd="${2:-}"

  if [[ -n "${explicit_cmd}" && "${explicit_cmd}" != "null" ]]; then
    ops_run_configured_command "${explicit_cmd}"
    return $?
  fi

  case "${action}" in
    start)
      run_cross_shell_binary npm start
      return $?
      ;;
    build)
      run_cross_shell_binary npm run build
      return $?
      ;;
    test)
      run_cross_shell_binary npm test
      return $?
      ;;
    lint)
      run_cross_shell_binary npm run lint
      return $?
      ;;
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
    *)
      return 10
      ;;
  esac
}
