#!/usr/bin/env bash
# .ops-core/commands/logs.sh — Multi-service log tailing.
#
# Usage: ops experimental logs [<service_id> | --all] [--follow]

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/setup.sh"

TARGET=""
FOLLOW=false

_usage_logs() {
  printf 'Usage: ops logs [<service_id> | --all] [--follow]\n'
}

for _arg in "$@"; do
  case "${_arg}" in
    help|--help|-h) _usage_logs; exit 0 ;;
    --all)
      if [[ -z "${TARGET}" ]]; then
        TARGET="--all"
      else
        die "Multiple targets not supported. Use '<service_id>' or '--all'."
      fi
      ;;
    --follow|-f) FOLLOW=true ;;
    -*)          die "Unknown flag: ${_arg}" ;;
    *)
      if [[ -z "${TARGET}" ]]; then
        TARGET="${_arg}"
      else
        die "Multiple targets not supported. Use '<service_id>' or '--all'."
      fi
      ;;
  esac
done

if [[ -z "${TARGET}" ]]; then
  _usage_logs >&2
  exit 2
fi

project_require_config_or_yaml

EXEC_LIST=()

if [[ "${TARGET}" == "--all" ]]; then
  mapfile -t EXEC_LIST < <(project_list_services | sort 2>/dev/null || true)
else
  if ! printf ' %s ' "$(project_list_services | tr '\n' ' ')" | grep -qF " ${TARGET} "; then
    ops_error "Unknown service: '${TARGET}'"
    exit 2
  fi
  EXEC_LIST=("${TARGET}")
fi

if [[ ${#EXEC_LIST[@]} -eq 0 ]]; then
  ops_ok "No services to tail logs for."
  exit 0
fi

# Track child PIDs to kill on exit
CHILD_PIDS=()

_cleanup_logs() {
  # Send TERM to all background tails to gracefully shut them down
  for pid in "${CHILD_PIDS[@]+"${CHILD_PIDS[@]}"}"; do
    kill -TERM "${pid}" 2>/dev/null || true
  done
}
trap '_cleanup_logs' EXIT INT TERM

ops_section "ops experimental logs"

for SVC in "${EXEC_LIST[@]+"${EXEC_LIST[@]}"}"; do
  STACK="$(project_get_service_field "${SVC}" stack)"
  RUNNER_KIND="$(project_get_service_field "${SVC}" runner.kind)"

  if [[ "${RUNNER_KIND}" == "compose" || "${STACK}" == "docker" ]]; then
    SVC_PATH="$(project_get_service_field "${SVC}" path)"
    ABS_PATH="${OPS_PROJECT_ROOT}/${SVC_PATH}"
    
    if [[ "${FOLLOW}" == "true" ]]; then
      (
        export OPS_LOG_SERVICE="${SVC}"
        cd "${ABS_PATH}" && docker compose logs -f 2>&1 | _ops_log_stream
      ) &
      CHILD_PIDS+=($!)
    else
      (
        export OPS_LOG_SERVICE="${SVC}"
        cd "${ABS_PATH}" && docker compose logs 2>&1 | _ops_log_stream
      ) &
      CHILD_PIDS+=($!)
    fi
  else
    RUNNER_KIND="$(project_get_service_field "${SVC}" runner.kind)"
    LOG_FILE="${OPS_PROJECT_LOG_DIR}/${SVC}.log"
    LOG_DIR="${OPS_PROJECT_LOG_DIR}/${SVC}"
    if [[ "${RUNNER_KIND}" == "process_group" && -d "${LOG_DIR}" ]]; then
      mapfile -t GROUP_LOGS < <(find "${LOG_DIR}" -maxdepth 1 -type f -name '*.log' | sort 2>/dev/null || true)
      if [[ ${#GROUP_LOGS[@]} -eq 0 ]]; then
        ops_warn "[${SVC}] No process log files found at .ops.project/logs/${SVC}/"
        continue
      fi

      if [[ "${FOLLOW}" == "true" ]]; then
        (
          export OPS_LOG_SERVICE="${SVC}"
          tail -F "${GROUP_LOGS[@]}" 2>&1 | _ops_log_stream
        ) &
        CHILD_PIDS+=($!)
      else
        (
          export OPS_LOG_SERVICE="${SVC}"
          cat "${GROUP_LOGS[@]}" 2>&1 | _ops_log_stream
        ) &
        CHILD_PIDS+=($!)
      fi
      continue
    fi

    if [[ ! -f "${LOG_FILE}" ]]; then
      ops_warn "[${SVC}] No log file found at .ops.project/logs/${SVC}.log"
      continue
    fi
    
    if [[ "${FOLLOW}" == "true" ]]; then
      (
        export OPS_LOG_SERVICE="${SVC}"
        tail -f "${LOG_FILE}" 2>&1 | _ops_log_stream
      ) &
      CHILD_PIDS+=($!)
    else
      (
        export OPS_LOG_SERVICE="${SVC}"
        cat "${LOG_FILE}" 2>&1 | _ops_log_stream
      ) &
      CHILD_PIDS+=($!)
    fi
  fi
done

wait
