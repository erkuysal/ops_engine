#!/usr/bin/env bash
# .ops-core/stacks/django.sh — Django/Python stack strategy stub.
# Phase 3 will implement the full action map: start, stop, build, test, lint, logs.

set -euo pipefail

# Contract: called with ACTION as $1 and EXPLICIT_CMD as $2
# Returns 10 (not-implemented) if action is unknown and no explicit command exists.
django_dispatch() {
  local action="${1:-}"
  local explicit_cmd="${2:-}"

  if [[ -n "${explicit_cmd}" && "${explicit_cmd}" != "null" ]]; then
    eval "${explicit_cmd}"
    return $?
  fi

  # Auto-detect and activate python environment (Conda or venv)
  if [[ -f "${OPS_PROJECT_ROOT}/.config" ]] && grep -q '^CONDA_ENV=' "${OPS_PROJECT_ROOT}/.config"; then
    local conda_env
    conda_env=$(grep -E '^CONDA_ENV=' "${OPS_PROJECT_ROOT}/.config" | cut -d= -f2 | tr -d '[:space:]')
    if type conda >/dev/null 2>&1; then
      eval "$(conda shell.bash hook)"
      conda activate "${conda_env}"
    fi
  elif [[ -f ".venv/bin/activate" ]]; then
    source ".venv/bin/activate"
  elif [[ -f "venv/bin/activate" ]]; then
    source "venv/bin/activate"
  fi

  case "${action}" in
    start)
      python manage.py runserver 0.0.0.0:8000
      return $?
      ;;
    test)
      python manage.py test
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
