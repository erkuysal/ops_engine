#!/usr/bin/env bash
# Execute configured shell commands in an isolated Bash process.

set -euo pipefail
if [[ "${_OPS_CORE_COMMAND_EXEC_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_COMMAND_EXEC_LOADED=1

ops_run_configured_command() {
  local command_text="${1:-}"

  if [[ -z "${command_text}" || "${command_text}" == "null" ]]; then
    return 10
  fi

  # Configured actions intentionally support shell syntax. Use a child shell so
  # expansions happen exactly once and cannot mutate the orchestrator shell.
  bash -c "${command_text}" --
}

return 0
