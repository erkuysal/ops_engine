#!/usr/bin/env bash
# .ops/core/lib/settings.sh — Config-first ops behavior settings.

set -euo pipefail
if [[ "${_OPS_CORE_SETTINGS_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_SETTINGS_LOADED=1

OPS_PROJECT_CONFIG_DIR="${OPS_PROJECT_CONFIG_DIR:-${OPS_PROJECT_ROOT}/.ops.project/config}"
OPS_PROJECT_CONFIG_SETTINGS_FILE="${OPS_PROJECT_CONFIG_SETTINGS_FILE:-${OPS_PROJECT_CONFIG_DIR}/settings.json}"
OPS_SETTINGS_SOURCE="${OPS_MANIFEST}"
export OPS_SETTINGS_SOURCE OPS_PROJECT_CONFIG_DIR OPS_PROJECT_CONFIG_SETTINGS_FILE

settings_source_path() {
  if [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]; then
    printf '%s' "${OPS_PROJECT_CONFIG_SETTINGS_FILE}"
  else
    printf '%s' "${OPS_SETTINGS_SOURCE}"
  fi
}

settings_exists() {
  [[ -f "${OPS_SETTINGS_SOURCE}" ]] || [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]
}

settings_validate() {
  if [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]; then
    require_bins jq
    jq -e '.settings // {} | type == "object"' "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" >/dev/null
    return $?
  fi
  [[ -f "${OPS_SETTINGS_SOURCE}" ]] || return 0
  require_bins yq
  yq e '.settings // {}' "${OPS_SETTINGS_SOURCE}" >/dev/null
}

ops_setting_get() {
  local expr="${1:?ops_setting_get: jq expression required}"
  local default="${2:-}"

  if [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]; then
    require_bins jq
    local config_value
    config_value="$(jq -r ".settings${expr} // \"\"" "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" 2>/dev/null || true)"
    if [[ -n "${config_value}" && "${config_value}" != "null" ]]; then
      printf '%s' "${config_value}"
    else
      printf '%s' "${default}"
    fi
    return 0
  fi

  if ! settings_exists; then
    printf '%s' "${default}"
    return 0
  fi

  require_bins yq
  local value
  value="$(yq e ".settings${expr} // \"\"" "${OPS_SETTINGS_SOURCE}" 2>/dev/null || true)"
  if [[ -z "${value}" || "${value}" == "null" ]]; then
    printf '%s' "${default}"
  else
    printf '%s' "${value}"
  fi
}

ops_setting_bool() {
  local expr="${1:?ops_setting_bool: jq expression required}"
  local default="${2:-false}"
  local value
  value="$(ops_setting_get "${expr}" "${default}")"
  case "${value}" in
    true|false) printf '%s' "${value}" ;;
    *) die "Invalid boolean setting ${expr}: '${value}' in $(settings_source_path)" 2 ;;
  esac
}

ops_setting_int() {
  local expr="${1:?ops_setting_int: jq expression required}"
  local default="${2:-0}"
  local value
  value="$(ops_setting_get "${expr}" "${default}")"
  if [[ "${value}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${value}"
  else
    die "Invalid integer setting ${expr}: '${value}' in $(settings_source_path)" 2
  fi
}

ops_setting_mode() {
  local expr="${1:?ops_setting_mode: jq expression required}"
  local default="${2:-foreground}"
  local value
  value="$(ops_setting_get "${expr}" "${default}")"
  case "${value}" in
    foreground|background) printf '%s' "${value}" ;;
    *) die "Invalid mode setting ${expr}: '${value}' in $(settings_source_path) (expected foreground or background)" 2 ;;
  esac
}
