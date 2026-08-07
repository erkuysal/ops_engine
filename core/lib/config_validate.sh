#!/usr/bin/env bash
# .ops/core/lib/config_validate.sh — Validate .ops.project/config JSON directly.

set -euo pipefail
if [[ "${_OPS_CORE_CONFIG_VALIDATE_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_CONFIG_VALIDATE_LOADED=1

# shellcheck source=manifest.sh
source "${OPS_CORE_ROOT}/lib/manifest.sh"
# shellcheck source=graph.sh
source "${OPS_CORE_ROOT}/lib/graph.sh"
# shellcheck source=global_profiles.sh
source "${OPS_CORE_ROOT}/lib/global_profiles.sh"

config_validate_available() {
  project_config_services_exists
}

_config_validate_version() {
  local file="$1" label="$2" err_fn="$3" warn_fn="$4"
  local version_type version_value

  if ! jq -e 'type == "object"' "${file}" >/dev/null 2>&1; then
    "$err_fn" "${label} — must contain a JSON object"
    return 0
  fi

  version_type="$(jq -r '.version | type' "${file}" 2>/dev/null || printf 'missing')"
  version_value="$(jq -r '.version // empty' "${file}" 2>/dev/null || true)"
  if [[ "${version_type}" == "number" && "${version_value}" == "1" ]]; then
    return 0
  fi
  if [[ "${version_type}" == "string" && "${version_value}" == "1" ]]; then
    "$warn_fn" "${label} — legacy string version \"1\"; regenerate config to store integer 1"
    return 0
  fi
  "$err_fn" "${label} — version must be integer 1"
}

config_validate_run() {
  local err_fn="${1:?config_validate_run: error function name required}"
  local warn_fn="${2:?config_validate_run: warn function name required}"
  local hint_fn="${3:?config_validate_run: hint function name required}"

  require_bins jq

  project_config_services_exists || {
    "$err_fn" "config — missing ${OPS_PROJECT_CONFIG_SERVICES_FILE}"
    return 1
  }

  local services_file="${OPS_PROJECT_CONFIG_SERVICES_FILE}"
  local settings_file="${OPS_PROJECT_CONFIG_SETTINGS_FILE}"
  local profiles_file="${OPS_PROJECT_CONFIG_PROFILES_FILE}"
  local project_file="${OPS_PROJECT_CONFIG_PROJECT_FILE}"
  local ci_file="${OPS_PROJECT_CONFIG_DIR}/ci.json"

  _config_validate_version "${services_file}" "services.json" "$err_fn" "$warn_fn"
  [[ -f "${project_file}" ]] && _config_validate_version "${project_file}" "project.json" "$err_fn" "$warn_fn"
  [[ -f "${settings_file}" ]] && _config_validate_version "${settings_file}" "settings.json" "$err_fn" "$warn_fn"
  [[ -f "${profiles_file}" ]] && _config_validate_version "${profiles_file}" "profiles.json" "$err_fn" "$warn_fn"

  # Structural: services.json
  if ! jq -e '.services | type == "array"' "${services_file}" >/dev/null 2>&1; then
    "$err_fn" "services.json — .services must be an array"
  fi

  local svc_count
  svc_count="$(jq '.services | length' "${services_file}" 2>/dev/null || printf '0')"
  if [[ "${svc_count}" == "0" || "${svc_count}" == "null" ]]; then
    "$err_fn" "services.json — services list is empty"
  fi

  if [[ -f "${project_file}" ]]; then
    local pname
    pname="$(jq -r '.name // ""' "${project_file}" 2>/dev/null || true)"
    [[ -z "${pname}" || "${pname}" == "null" ]] && "$warn_fn" "project.json — name not set"
  else
    "$warn_fn" "project.json — missing (optional but recommended)"
  fi

  if [[ -f "${settings_file}" ]]; then
    jq -e '.settings // {} | type == "object"' "${settings_file}" >/dev/null 2>&1 || \
      "$err_fn" "settings.json — .settings must be an object"
    jq -e '.setup // {} | type == "object"' "${settings_file}" >/dev/null 2>&1 || \
      "$err_fn" "settings.json — .setup must be an object"
  fi

  if [[ -f "${profiles_file}" ]]; then
    jq -e '.profiles // {} | type == "object"' "${profiles_file}" >/dev/null 2>&1 || \
      "$err_fn" "profiles.json — .profiles must be an object"
  fi

  if [[ -f "${ci_file}" ]]; then
    local global_profile_ref
    global_profile_ref="$(jq -r '.global_profile // ""' "${ci_file}" 2>/dev/null || true)"
    if [[ -n "${global_profile_ref}" ]] && ! global_profile_exists "${global_profile_ref}"; then
      "$warn_fn" "ci.json — global profile '${global_profile_ref}' is not installed on this machine (run: ops global setup ${global_profile_ref} --interactive --apply)"
    fi
  fi

  # Semantic: per service
  mapfile -t _cfg_ids < <(jq -r '.services[]?.id // empty' "${services_file}" 2>/dev/null || true)
  declare -A _cfg_id_seen=()
  local id stack path env_policy dep
  for id in "${_cfg_ids[@]+"${_cfg_ids[@]}"}"; do
    [[ -z "${id}" || "${id}" == "null" ]] && continue
    if [[ -n "${_cfg_id_seen[${id}]:-}" ]]; then
      "$err_fn" "services.${id} — duplicate service id"
    fi
    _cfg_id_seen["${id}"]=1

    stack="$(jq -r --arg id "${id}" '.services[] | select(.id == $id) | .stack // ""' "${services_file}")"
    if [[ -z "${stack}" || "${stack}" == "null" ]]; then
      "$err_fn" "services.${id}.stack — required field missing"
    else
      local valid_stack=false s
      for s in "${OPS_KNOWN_STACKS[@]}"; do
        [[ "${stack}" == "${s}" ]] && valid_stack=true && break
      done
      [[ "${valid_stack}" == false ]] && \
        "$err_fn" "services.${id}.stack — unknown stack '${stack}'. Known: ${OPS_KNOWN_STACKS[*]}"
    fi

    path="$(jq -r --arg id "${id}" '.services[] | select(.id == $id) | .path // ""' "${services_file}")"
    [[ -z "${path}" || "${path}" == "null" ]] && \
      "$err_fn" "services.${id}.path — required field missing"

    env_policy="$(jq -r --arg id "${id}" '.services[] | select(.id == $id) | .env_policy // "dev_file"' "${services_file}")"
    if [[ -n "${env_policy}" && "${env_policy}" != "null" ]]; then
      local valid_policy=false p
      for p in "${OPS_VALID_ENV_POLICIES[@]}"; do
        [[ "${env_policy}" == "${p}" ]] && valid_policy=true && break
      done
      [[ "${valid_policy}" == false ]] && \
        "$err_fn" "services.${id}.env_policy — invalid '${env_policy}'"
    fi

    local start_action
    start_action="$(jq -r --arg id "${id}" '.services[] | select(.id == $id) | .actions.start // ""' "${services_file}")"
    if [[ -z "${start_action}" || "${start_action}" == "null" ]]; then
      local setup_cmd
      setup_cmd="$(jq -r --arg id "${id}" '.services[] | select(.id == $id) | .setup.command // ""' "${services_file}")"
      [[ -z "${setup_cmd}" || "${setup_cmd}" == "null" ]] && \
        "$hint_fn" "services.${id} — no explicit start action (stack default may apply)"
    fi
  done

  # Fix id_seen for depends_on check — rebuild set
  for id in "${_cfg_ids[@]+"${_cfg_ids[@]}"}"; do
    [[ -z "${id}" ]] && continue
    while IFS= read -r dep; do
      [[ -z "${dep}" || "${dep}" == "null" ]] && continue
      if ! jq -e --arg dep "${dep}" '.services[] | select(.id == $dep)' "${services_file}" >/dev/null 2>&1; then
        "$err_fn" "services.${id}.depends_on — references unknown service '${dep}'"
      fi
    done < <(jq -r --arg id "${id}" '.services[] | select(.id == $id) | .depends_on[]?' "${services_file}" 2>/dev/null || true)
  done

  graph_cycle_check 2>/dev/null || "$err_fn" "services — dependency cycle detected"

  # Filesystem
  for id in "${_cfg_ids[@]+"${_cfg_ids[@]}"}"; do
    [[ -z "${id}" ]] && continue
    path="$(jq -r --arg id "${id}" '.services[] | select(.id == $id) | .path // ""' "${services_file}")"
    if [[ -n "${path}" && "${path}" != "null" ]]; then
      [[ -d "${OPS_PROJECT_ROOT}/${path}" ]] || \
        "$err_fn" "services.${id}.path — directory not found: '${path}'"
    fi

    env_policy="$(jq -r --arg id "${id}" '.services[] | select(.id == $id) | .env_policy // "dev_file"' "${services_file}")"
    if [[ "${env_policy}" == "dev_file" || "${env_policy}" == "mixed" ]]; then
      local ef
      while IFS= read -r ef; do
        [[ -z "${ef}" || "${ef}" == "null" ]] && continue
        [[ -f "${OPS_PROJECT_ROOT}/${ef}" ]] || \
          "$warn_fn" "services.${id}.env_files — not found: '${ef}'"
      done < <(jq -r --arg id "${id}" '.services[] | select(.id == $id) | .env_files[]?' "${services_file}" 2>/dev/null || true)
    fi
  done

  [[ -d "${OPS_PROJECT_STATE_DIR}" ]] || \
    "$warn_fn" ".ops.project/ — state directory missing (run ops setup --apply)"

  return 0
}

return 0
