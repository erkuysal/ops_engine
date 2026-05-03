#!/usr/bin/env bash
# .ops-core/stacks/node.sh — Node.js stack strategy stub.
# Phase 3 will implement the full action map.

set -euo pipefail

node_dispatch() {
  local action="${1:-}"
  local explicit_cmd="${2:-}"

  if [[ -n "${explicit_cmd}" && "${explicit_cmd}" != "null" ]]; then
    eval "${explicit_cmd}"
    return $?
  fi

  case "${action}" in
    start)
      npm start
      return $?
      ;;
    build)
      npm run build
      return $?
      ;;
    test)
      npm test
      return $?
      ;;
    lint)
      npm run lint
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
