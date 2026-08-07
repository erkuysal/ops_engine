#!/usr/bin/env bash
# .ops-core/stacks/elixir-phoenix.sh — Elixir/Phoenix (Mix) stack strategy stub.
# Phase 3 will implement the full action map (mix phx.server, mix deps.get, etc.)

set -euo pipefail

_ELIXIR_STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/command_exec.sh
source "${_ELIXIR_STACK_DIR}/../lib/command_exec.sh"

elixir_phoenix_dispatch() {
  local action="${1:-}"
  local explicit_cmd="${2:-}"

  if [[ -n "${explicit_cmd}" && "${explicit_cmd}" != "null" ]]; then
    ops_run_configured_command "${explicit_cmd}"
    return $?
  fi

  case "${action}" in
    start)
      mix phx.server
      return $?
      ;;
    test)
      mix test
      return $?
      ;;
    build)
      mix release
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
