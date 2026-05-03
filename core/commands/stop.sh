#!/usr/bin/env bash
# .ops-core/commands/stop.sh — Dependency-aware recursive stop.
#
# Usage: ops experimental stop [<service_id> | --all] [--with-deps | --no-deps]
#
# Flags:
#   --with-deps  Stop dependents and then requested service(s) (Default)
#   --no-deps    Only stop the requested service(s)

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/graph.sh"

TARGET=""
WITH_DEPS=true

_usage_stop() {
  printf 'Usage: ops stop [<service_id> | --all] [--with-deps | --no-deps]\n'
}

for _arg in "$@"; do
  case "${_arg}" in
    help|--help|-h) _usage_stop; exit 0 ;;
    --all)
      if [[ -z "${TARGET}" ]]; then
        TARGET="--all"
      else
        die "Multiple targets not supported. Use '<service_id>' or '--all'."
      fi
      ;;
    --with-deps) WITH_DEPS=true ;;
    --no-deps)   WITH_DEPS=false ;;
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
  _usage_stop >&2
  exit 2
fi

require_manifest
graph_cycle_check

EXEC_LIST=()

if [[ "${TARGET}" == "--all" ]]; then
  read -ra EXEC_LIST <<< "$(graph_reverse_topo_sort "--all")"
else
  if ! printf ' %s ' "$(manifest_list_services | tr '\n' ' ')" | grep -qF " ${TARGET} "; then
    ops_error "Unknown service: '${TARGET}'"
    exit 2
  fi
  
  if [[ "${WITH_DEPS}" == "true" ]]; then
    read -ra EXEC_LIST <<< "$(graph_reverse_topo_sort "${TARGET}")"
  else
    EXEC_LIST=("${TARGET}")
  fi
fi

ops_section "ops experimental stop"

if [[ ${#EXEC_LIST[@]} -eq 0 ]]; then
  ops_ok "Nothing to stop."
  exit 0
fi

ops_info "Execution order: ${EXEC_LIST[*]}"
printf '\n'

for SVC in "${EXEC_LIST[@]+"${EXEC_LIST[@]}"}"; do
  STATUS_CODE=1
  if bash "${_SELF_DIR}/run.sh" "status" "${SVC}" >/dev/null 2>&1; then
    STATUS_CODE=0
  else
    STATUS_CODE=$?
  fi

  if [[ ${STATUS_CODE} -eq 1 ]]; then
    ops_ok "[${SVC}] Already stopped (skipped)"
  else
    ops_info "[${SVC}] Stopping..."
    if ! bash "${_SELF_DIR}/run.sh" "stop" "${SVC}"; then
      ops_error "Failed to stop '${SVC}'"
    fi
  fi
done

printf '\n'
ops_ok "Stop sequence complete."
