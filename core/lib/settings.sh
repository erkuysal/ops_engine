#!/usr/bin/env bash
# .ops/core/lib/settings.sh — Ops behavior defaults from root .ops.yaml.

set -euo pipefail
if [[ "${_OPS_CORE_SETTINGS_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_SETTINGS_LOADED=1

OPS_SETTINGS_SOURCE="${OPS_MANIFEST}"
OPS_PROJECT_CONFIG_DIR="${OPS_PROJECT_CONFIG_DIR:-${OPS_PROJECT_ROOT}/.ops.project/config}"
OPS_PROJECT_CONFIG_SETTINGS_FILE="${OPS_PROJECT_CONFIG_SETTINGS_FILE:-${OPS_PROJECT_CONFIG_DIR}/settings.json}"
export OPS_SETTINGS_SOURCE OPS_PROJECT_CONFIG_DIR OPS_PROJECT_CONFIG_SETTINGS_FILE

settings_exists() {
  [[ -f "${OPS_SETTINGS_SOURCE}" ]] || [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]
}

settings_validate() {
  require_bins jq yq
  if [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]; then
    jq -e '.settings // {} | type == "object"' "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" >/dev/null
    return $?
  fi
  [[ -f "${OPS_SETTINGS_SOURCE}" ]] || return 0
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
      return 0
    fi
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
    *) die "Invalid boolean setting ${expr}: '${value}' in ${OPS_SETTINGS_SOURCE}" 2 ;;
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
    die "Invalid integer setting ${expr}: '${value}' in ${OPS_SETTINGS_SOURCE}" 2
  fi
}

ops_setting_mode() {
  local expr="${1:?ops_setting_mode: jq expression required}"
  local default="${2:-foreground}"
  local value
  value="$(ops_setting_get "${expr}" "${default}")"
  case "${value}" in
    foreground|background) printf '%s' "${value}" ;;
    *) die "Invalid mode setting ${expr}: '${value}' in ${OPS_SETTINGS_SOURCE} (expected foreground or background)" 2 ;;
  esac
}
