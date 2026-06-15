#!/usr/bin/env bash
# .ops/core/lib/env_discovery.sh — Discover .env files for setup and services.

set -euo pipefail
if [[ "${_OPS_CORE_ENV_DISCOVERY_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_ENV_DISCOVERY_LOADED=1

# Preferred env filenames (service-local), highest priority first.
_ENV_DISCOVERY_SERVICE_CANDIDATES=(
  .env.local
  .env.development.local
  .env.development
  .env.dev
  .env
)

_ENV_DISCOVERY_GLOBAL_CANDIDATES=(
  .env.local
  .env.development
  .env
)

env_discovery_is_example_name() {
  local name="${1:?env_discovery_is_example_name: name required}"
  case "${name}" in
    .env.example|.env.sample|.env.template|.env.dist|.env.example.*) return 0 ;;
  esac
  [[ "${name}" == *.example ]] || [[ "${name}" == *.sample ]] || [[ "${name}" == *.template ]]
}

env_discovery_is_deploy_name() {
  local name="${1:?env_discovery_is_deploy_name: name required}"
  case "${name}" in
    .env.staging|.staging.env|.env.production|.production.env|.env.prod|.prod.env) return 0 ;;
  esac
  return 1
}

env_discovery_profile() {
  printf '%s' "${OPS_SETUP_PROFILE:-local}"
}

env_discovery_profile_allows_deploy_name() {
  local name="${1:?env_discovery_profile_allows_deploy_name: name required}"
  local profile
  profile="$(env_discovery_profile)"
  case "${profile}:${name}" in
    staging:.env.staging|staging:.staging.env) return 0 ;;
    production:.env.production|production:.production.env|production:.env.prod|production:.prod.env) return 0 ;;
    prod:.env.production|prod:.production.env|prod:.env.prod|prod:.prod.env) return 0 ;;
  esac
  return 1
}

env_discovery_should_skip_deploy_name() {
  local name="${1:?env_discovery_should_skip_deploy_name: name required}"
  env_discovery_is_deploy_name "${name}" || return 1
  env_discovery_profile_allows_deploy_name "${name}" && return 1
  return 0
}

env_discovery_profile_candidates() {
  local profile
  profile="$(env_discovery_profile)"
  case "${profile}" in
    staging)
      printf '%s\n' .env.staging .staging.env
      ;;
    production|prod)
      printf '%s\n' .env.production .production.env .env.prod .prod.env
      ;;
  esac
}

env_discovery_rel_path() {
  local dir_rel="$1"
  local filename="$2"
  if [[ -z "${dir_rel}" || "${dir_rel}" == "." ]]; then
    printf '%s' "${filename}"
  else
    printf '%s/%s' "${dir_rel}" "${filename}"
  fi
}

env_discovery_array_to_json() {
  if [[ $# -eq 0 ]]; then
    printf '[]'
    return 0
  fi
  jq -n '$ARGS.positional' --args "$@"
}

# Collect env file paths relative to OPS_PROJECT_ROOT for one directory.
env_discovery_files_in_dir_json() {
  local abs_dir="${1:?env_discovery_files_in_dir_json: abs dir required}"
  local dir_rel="${2:-}"
  local -a found=() name rel candidate abs_path has_non_example=false
  local -A seen=()

  [[ -d "${abs_dir}" ]] || {
    printf '[]'
    return 0
  }

  for candidate in "${_ENV_DISCOVERY_SERVICE_CANDIDATES[@]}"; do
    abs_path="${abs_dir}/${candidate}"
    [[ -f "${abs_path}" ]] || continue
    if env_discovery_is_example_name "${candidate}"; then
      continue
    fi
    has_non_example=true
    rel="$(env_discovery_rel_path "${dir_rel}" "${candidate}")"
    [[ -n "${seen[${rel}]:-}" ]] && continue
    seen["${rel}"]=1
    found+=("${rel}")
  done

  while IFS= read -r candidate; do
    [[ -z "${candidate}" ]] && continue
    abs_path="${abs_dir}/${candidate}"
    [[ -f "${abs_path}" ]] || continue
    env_discovery_is_example_name "${candidate}" && continue
    rel="$(env_discovery_rel_path "${dir_rel}" "${candidate}")"
    [[ -n "${seen[${rel}]:-}" ]] && continue
    seen["${rel}"]=1
    found+=("${rel}")
    has_non_example=true
  done < <(env_discovery_profile_candidates)

  while IFS= read -r abs_path; do
    [[ -z "${abs_path}" ]] && continue
    name="$(basename "${abs_path}")"
    [[ "${name}" == ".env" ]] && continue
    env_discovery_is_example_name "${name}" && continue
    env_discovery_should_skip_deploy_name "${name}" && continue
    rel="$(env_discovery_rel_path "${dir_rel}" "${name}")"
    [[ -n "${seen[${rel}]:-}" ]] && continue
    seen["${rel}"]=1
    found+=("${rel}")
    has_non_example=true
  done < <(find "${abs_dir}" -maxdepth 1 -type f -name '.env.*' 2>/dev/null | LC_ALL=C sort)

  if [[ "${has_non_example}" == "false" ]]; then
    for candidate in .env.example .env.sample; do
      abs_path="${abs_dir}/${candidate}"
      [[ -f "${abs_path}" ]] || continue
      rel="$(env_discovery_rel_path "${dir_rel}" "${candidate}")"
      [[ -n "${seen[${rel}]:-}" ]] && continue
      seen["${rel}"]=1
      found+=("${rel}")
    done
  fi

  env_discovery_array_to_json "${found[@]+"${found[@]}"}"
}

env_discovery_global_files_json() {
  env_discovery_files_in_dir_json "${OPS_PROJECT_ROOT}" ""
}

env_discovery_service_files_json() {
  local service_rel="${1:?env_discovery_service_files_json: service path required}"
  local abs_dir="${OPS_PROJECT_ROOT}/${service_rel}"
  local -a found=() item
  local service_json root_json merged_json

  service_json="$(env_discovery_files_in_dir_json "${abs_dir}" "${service_rel}")"

  if [[ "$(jq 'length' <<< "${service_json}")" -gt 0 ]]; then
    printf '%s' "${service_json}"
    return 0
  fi

  root_json="$(env_discovery_global_files_json)"
  if [[ "$(jq 'length' <<< "${root_json}")" -gt 0 ]]; then
    printf '%s' "${root_json}"
    return 0
  fi

  local parent_rel parent_abs
  parent_rel="$(dirname "${service_rel}")"
  if [[ "${parent_rel}" != "." && "${parent_rel}" != "${service_rel}" ]]; then
    parent_abs="${OPS_PROJECT_ROOT}/${parent_rel}"
    env_discovery_files_in_dir_json "${parent_abs}" "${parent_rel}"
    return 0
  fi

  printf '[]'
}

env_discovery_attach_to_entry_json() {
  local entry_json="$1"
  local rel_path="$2"
  jq \
    --argjson env_files "$(env_discovery_service_files_json "${rel_path}")" \
    '. + {env_files: $env_files}' \
    <<< "${entry_json}"
}

return 0
