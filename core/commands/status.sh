#!/usr/bin/env bash
# .ops/core/commands/status.sh — Aggregate service runtime status.
#
# Usage:
#   ops status [service_id] [--json]
#   ops ps [service_id] [--json]

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/output.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/setup.sh"
source "${_SELF_DIR}/../lib/status.sh"

TARGET=""
JSON=false

_usage_status() {
  cat <<'EOF'
Usage: ops status [service_id] [--json]
       ops ps [service_id] [--json]

Show runtime status for one service or all configured services.

Reads PID files under .ops.project/run/ and service metadata from
.ops.project/config, with .ops.yaml only as a compatibility fallback.

States:
  running   All tracked processes are alive
  partial   Some processes alive (process groups)
  stopped   No live processes
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    help|--help|-h)
      _usage_status
      exit 0
      ;;
    --json)
      JSON=true
      ;;
    --plain)
      OPS_PLAIN=true
      ;;
    --*)
      die "Unknown flag: $1. Use --help." 2
      ;;
    *)
      if [[ -z "${TARGET}" ]]; then
        TARGET="$1"
      else
        die "Multiple service IDs not supported. Use one id or omit for all." 2
      fi
      ;;
  esac
  shift
done

project_require_config_or_yaml

if [[ -n "${TARGET}" ]]; then
  if ! project_service_exists "${TARGET}"; then
    die "Unknown service: '${TARGET}'" 2
  fi
fi

if [[ "${JSON}" == "true" ]]; then
  require_bins jq
  if [[ -n "${TARGET}" ]]; then
    status_service_json "${TARGET}" | ops_json_envelope "status"
  else
    status_all_json | ops_json_envelope "status"
  fi
  exit 0
fi

ops_section "ops status"

if [[ -n "${TARGET}" ]]; then
  ops_info "Service: ${TARGET}"
else
  ops_info "All services"
fi
printf '  project config source: %s\n\n' "$(status_config_source_rel)"

_print_row() {
  local svc_id="$1"
  local name stack state pids port health
  name="$(project_get_service_field "${svc_id}" name)"
  stack="$(project_get_service_field "${svc_id}" stack)"
  state="$(status_aggregate_state "${svc_id}")"
  pids="$(status_format_pids "${svc_id}")"
  port="$(status_service_port "${svc_id}")"
  health="$(status_service_healthcheck "${svc_id}")"
  [[ -z "${pids}" ]] && pids="-"
  [[ -z "${port}" || "${port}" == "0" ]] && port="-"
  [[ -z "${health}" || "${health}" == "null" ]] && health="-"

  if [[ "${OPS_PLAIN}" == "true" ]]; then
    printf '%-14s %-10s %-8s %-22s %-6s %s\n' \
      "${svc_id}" "${stack}" "${state}" "${pids}" "${port}" "${health}"
  else
    local state_color="${OPS_DIM}"
    case "${state}" in
      running) state_color="${OPS_GREEN}" ;;
      partial) state_color="${OPS_YELLOW}" ;;
      stopped) state_color="${OPS_RED}" ;;
    esac
    printf '  %-14s %-10s %s%-8s%s %-22s %-6s %s\n' \
      "${svc_id}" "${stack}" "${state_color}" "${state}" "${OPS_NC}" "${pids}" "${port}" "${health}"
  fi
}

if [[ "${OPS_PLAIN}" == "true" ]]; then
  printf '%-14s %-10s %-8s %-22s %-6s %s\n' "SERVICE" "STACK" "STATE" "PID(S)" "PORT" "HEALTH"
  printf '%-14s %-10s %-8s %-22s %-6s %s\n' "-------" "-----" "-----" "------" "----" "------"
else
  printf '  %-14s %-10s %-8s %-22s %-6s %s\n' "SERVICE" "STACK" "STATE" "PID(S)" "PORT" "HEALTH"
fi

if [[ -n "${TARGET}" ]]; then
  _print_row "${TARGET}"
else
  while IFS= read -r svc_id; do
    [[ -z "${svc_id}" ]] && continue
    _print_row "${svc_id}"
  done < <(project_list_services)
fi

printf '\n'
ops_info "Tip: ops status --json for machine-readable output"
