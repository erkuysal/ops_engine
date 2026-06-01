#!/usr/bin/env bash
# .ops/core/lib/healthcheck.sh — HTTP health probes for service startup.

set -euo pipefail
if [[ "${_OPS_CORE_HEALTHCHECK_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_HEALTHCHECK_LOADED=1

# shellcheck source=manifest.sh
source "${OPS_CORE_ROOT}/lib/manifest.sh"
# shellcheck source=status.sh
source "${OPS_CORE_ROOT}/lib/status.sh"
# shellcheck source=settings.sh
source "${OPS_CORE_ROOT}/lib/settings.sh"

healthcheck_service_url() {
  local svc_id="${1:?healthcheck_service_url: service id required}"
  local url port

  url="$(status_service_healthcheck "${svc_id}")"
  url="${url//[$'\t\r\n']/}"
  if [[ -n "${url}" && "${url}" != "null" ]]; then
    printf '%s' "${url}"
    return 0
  fi

  port="$(status_service_port "${svc_id}")"
  if [[ "${port}" =~ ^[0-9]+$ && "${port}" -gt 0 ]]; then
    printf 'http://localhost:%s/' "${port}"
    return 0
  fi

  return 1
}

healthcheck_url_is_http() {
  local url="${1:-}"
  [[ "${url}" =~ ^https?:// ]]
}

healthcheck_probe_url() {
  local url="${1:?healthcheck_probe_url: url required}"
  local connect_timeout="${2:-2}"
  local max_time="${3:-5}"

  healthcheck_url_is_http "${url}" || return 1
  command -v curl >/dev/null 2>&1 || return 2

  curl -sS -o /dev/null \
    --connect-timeout "${connect_timeout}" \
    -m "${max_time}" \
    "${url}" >/dev/null 2>&1
}

healthcheck_wait_url() {
  local url="${1:?healthcheck_wait_url: url required}"
  local timeout_seconds="${2:-60}"
  local interval_seconds="${3:-1}"
  local elapsed=0

  healthcheck_url_is_http "${url}" || return 1
  command -v curl >/dev/null 2>&1 || return 2
  [[ "${timeout_seconds}" =~ ^[0-9]+$ ]] || timeout_seconds=60
  [[ "${interval_seconds}" =~ ^[0-9]+$ ]] || interval_seconds=1
  (( interval_seconds > 0 )) || interval_seconds=1

  while (( elapsed < timeout_seconds )); do
    if healthcheck_probe_url "${url}"; then
      return 0
    fi
    sleep "${interval_seconds}"
    elapsed=$((elapsed + interval_seconds))
  done

  return 1
}

healthcheck_wait_service() {
  local svc_id="${1:?healthcheck_wait_service: service id required}"
  local url timeout interval

  url="$(healthcheck_service_url "${svc_id}" 2>/dev/null || true)"
  [[ -n "${url}" ]] || return 0

  timeout="$(ops_setting_int '.start.healthcheck.timeout_seconds' '60')"
  interval="$(ops_setting_int '.start.healthcheck.interval_seconds' '1')"

  healthcheck_wait_url "${url}" "${timeout}" "${interval}"
}

return 0
