#!/usr/bin/env bash
# .ops/core/commands/setup.sh — Project setup generation, inspection, and checks.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/setup.sh"
source "${_SELF_DIR}/../lib/discovery.sh"

SUBCMD=""
PROFILE=""
DRY_RUN=false
APPLY=false
INTERACTIVE=false

_usage_setup() {
  cat <<'EOF'
Usage: ops setup [--profile NAME] [--dry-run] [--apply]
       ops setup init [--profile NAME] [--apply]
       ops setup --interactive [--profile NAME] [--apply]
       ops setup discover [--apply]
       ops setup show [--profile NAME]
       ops setup doctor [--profile NAME]

Generates and validates project setup values:
  .ops.yaml setup/settings/profiles sections
  .ops.project/ generated state directories
  .ops.project/generated/discovery.json workspace discovery cache
  scripts/project_structure.json and scripts/project_values.json metadata

By default, generated setup values are empty/project-neutral. Use the
interactive flow to fill project-specific scaffold/runtime values.
EOF
}

if [[ $# -gt 0 ]]; then
  case "${1}" in
    init|interactive)
      SUBCMD="generate"
      INTERACTIVE=true
      shift
      ;;
    discover|show|doctor|help|--help|-h)
      SUBCMD="$1"
      shift
      ;;
  esac
fi

for _arg in "$@"; do
  case "${_arg}" in
    --dry-run) DRY_RUN=true ;;
    --apply) APPLY=true ;;
    --interactive) INTERACTIVE=true ;;
    --profile=*) PROFILE="${_arg#*=}" ;;
    --profile)
      die "--profile requires --profile=name form for now" 2
      ;;
    --help|-h)
      _usage_setup
      exit 0
      ;;
    *) die "Unknown flag: ${_arg}. Use --help." ;;
  esac
done

[[ -z "${SUBCMD}" ]] && SUBCMD="generate"
[[ "${SUBCMD}" == "help" || "${SUBCMD}" == "--help" || "${SUBCMD}" == "-h" ]] && { _usage_setup; exit 0; }
[[ -z "${PROFILE}" ]] && PROFILE="$(setup_default_profile)"

_service_default_command() {
  local id="$1" stack="$2"
  setup_stack_default_command "${stack}" start
}

_service_default_port() {
  printf '0'
}

_generate_setup_json() {
  require_bins jq

  local services_json="{}"
  local id stack cmd port service_entry
  while IFS= read -r id; do
    [[ -z "${id}" || "${id}" == "null" ]] && continue
    stack="$(manifest_get_service_field "${id}" stack)"
    cmd="$(_service_default_command "${id}" "${stack}")"
    port="$(_service_default_port "${id}" "${stack}")"
    service_entry="$(jq -n --arg cmd "${cmd}" --argjson port "${port}" '{runtime: "", port: $port, command: $cmd, env_files: []}')"
    if [[ "${stack}" == "django" ]]; then
      service_entry="$(jq '. + {django: {conda_env: ""}}' <<< "${service_entry}")"
    fi
    services_json="$(jq \
      --arg id "${id}" \
      --argjson entry "${service_entry}" \
      '. + {($id): $entry}' \
      <<< "${services_json}")"
  done < <(manifest_list_services)

  jq -n \
    --argjson services "${services_json}" \
    '{
      default_profile: "",
      scaffold: {type: "", package_manager: "", template: ""},
      runtimes: {python: {manager: "", env: "", fallbacks: []}},
      services: $services
    }'
}

_prompt_value() {
  local label="$1" default="${2:-}" value
  if [[ -n "${default}" ]]; then
    read -r -p "${label} [${default}]: " value
    printf '%s' "${value:-${default}}"
  else
    read -r -p "${label}: " value
    printf '%s' "${value}"
  fi
}

_prompt_yes_no() {
  local label="$1" default="${2:-n}" value
  read -r -p "${label} [${default}]: " value
  value="${value:-${default}}"
  case "${value}" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

_interactive_setup_json() {
  require_bins jq
  local default_profile scaffold_type package_manager template python_manager python_env fallbacks
  default_profile="$(_prompt_value "Default profile" "${PROFILE}")"
  scaffold_type="$(_prompt_value "Scaffold type (empty, node, python, django, custom)" "")"
  package_manager="$(_prompt_value "Package manager (npm, pnpm, yarn, pip, poetry, uv, empty)" "")"
  template="$(_prompt_value "Scaffold template/name" "")"
  python_manager="$(_prompt_value "Python manager (conda, venv, pyenv, system, empty)" "")"
  python_env="$(_prompt_value "Python environment name/path" "")"
  fallbacks="$(_prompt_value "Python fallbacks, comma-separated" "")"

  local services_json="{}"
  local id stack runtime port command env_files env_json django_conda_env service_entry
  while IFS= read -r id; do
    [[ -z "${id}" || "${id}" == "null" ]] && continue
    stack="$(manifest_get_service_field "${id}" stack)"
    printf '\nService %s (%s)\n' "${id}" "${stack}" >&2
    runtime="$(_prompt_value "  Runtime" "")"
    port="$(_prompt_value "  Port (0 for none/unknown)" "0")"
    [[ "${port}" =~ ^[0-9]+$ ]] || port="0"
    command="$(_prompt_value "  Start command" "$(_service_default_command "${id}" "${stack}")")"
    env_files="$(_prompt_value "  Env files, comma-separated" "")"
    django_conda_env=""
    if [[ "${stack}" == "django" ]]; then
      django_conda_env="$(_prompt_value "  Django Conda env (empty to keep prompt fallback)" "${python_env}")"
    fi
    env_json="$(jq -Rn --arg raw "${env_files}" '$raw | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')"
    service_entry="$(jq -n \
      --arg runtime "${runtime}" \
      --arg command "${command}" \
      --argjson port "${port:-0}" \
      --argjson env_files "${env_json}" \
      '{runtime: $runtime, port: $port, command: $command, env_files: $env_files}')"
    if [[ "${stack}" == "django" ]]; then
      service_entry="$(jq --arg conda_env "${django_conda_env}" '. + {django: {conda_env: $conda_env}}' <<< "${service_entry}")"
    fi
    services_json="$(jq \
      --arg id "${id}" \
      --argjson entry "${service_entry}" \
      '. + {($id): $entry}' \
      <<< "${services_json}")"
  done < <(manifest_list_services)

  jq -n \
    --arg default_profile "${default_profile}" \
    --arg scaffold_type "${scaffold_type}" \
    --arg package_manager "${package_manager}" \
    --arg template "${template}" \
    --arg python_manager "${python_manager}" \
    --arg python_env "${python_env}" \
    --arg fallbacks "${fallbacks}" \
    --argjson services "${services_json}" \
    '{
      default_profile: $default_profile,
      scaffold: {type: $scaffold_type, package_manager: $package_manager, template: $template},
      runtimes: {
        python: {
          manager: $python_manager,
          env: $python_env,
          fallbacks: ($fallbacks | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))
        }
      },
      services: $services
    }'
}

_generate_profile_json() {
  local profile="$1"
  jq -n '{remote: {host: "", user: "", path: "", ssh_key_path: ""}, docker: {network: "", compose_files: []}, healthchecks: {}, certificates: {provider: "", domain: ""}}'
}

_print_discovery_preview() {
  local discovery_json="$1"

  printf '\nDiscovery\n'
  jq -r '
    .directories[]
    | [
        (.id // ""),
        (.path // ""),
        (.stack // ""),
        (.role // ""),
        (if .service then "service" else "non-service" end),
        ((.confidence // 0) | tostring),
        ((.evidence // []) | join(", "))
      ]
    | @tsv
  ' <<< "${discovery_json}" |
    while IFS=$'\t' read -r id path stack role service confidence evidence; do
      printf '  %-14s %-34s %-15s %-16s %-11s conf=%s  [%s]\n' \
        "${id}" "${path}" "${stack}" "${role}" "${service}" "${confidence}" "${evidence}"
    done

  printf '\nService Candidates\n'
  jq -r '
    .directories[]
    | select(.service == true)
    | [
        (.id // ""),
        (.path // ""),
        (.stack // ""),
        (.role // "")
      ]
    | @tsv
  ' <<< "${discovery_json}" |
    while IFS=$'\t' read -r id path stack role; do
      printf '  + %-14s %-34s %-15s %s\n' "${id}" "${path}" "${stack}" "${role}"
    done

  printf '\nSkipped By Default\n'
  jq -r '
    .directories[]
    | select(.service != true)
    | [
        (.id // ""),
        (.path // ""),
        (.role // "")
      ]
    | @tsv
  ' <<< "${discovery_json}" |
    while IFS=$'\t' read -r id path role; do
      printf '  - %-14s %-34s %s\n' "${id}" "${path}" "${role}"
    done
}

_run_discovery() {
  require_bins jq
  local discovery_json discovery_file

  ops_section "ops setup discover"
  discovery_json="$(discovery_scan_project_json)"
  _print_discovery_preview "${discovery_json}"

  if [[ "${APPLY}" == "true" ]]; then
    ensure_dir "${OPS_PROJECT_STATE_DIR}"
    ensure_dir "${OPS_PROJECT_GENERATED_DIR}"
    discovery_file="$(discovery_write_project_json)"
    printf '\n'
    ops_ok "Wrote ${discovery_file#${OPS_PROJECT_ROOT}/}"
  else
    printf '\n'
    ops_info "Preview only. Use --apply to write .ops.project/generated/discovery.json."
  fi
}

_interactive_profile_json() {
  require_bins jq
  local host user path ssh_key docker_network compose_files cert_provider cert_domain health_name health_url healthchecks_json compose_json
  host=""
  user=""
  path=""
  ssh_key=""
  if [[ "${PROFILE}" != "local" ]] || _prompt_yes_no "Configure remote/VPS values for profile '${PROFILE}'?" "n"; then
    host="$(_prompt_value "Remote host" "")"
    user="$(_prompt_value "Remote user" "")"
    path="$(_prompt_value "Remote path" "")"
    ssh_key="$(_prompt_value "SSH key path" "")"
  fi

  docker_network="$(_prompt_value "Docker network" "")"
  compose_files="$(_prompt_value "Docker compose files, comma-separated" "")"
  cert_provider="$(_prompt_value "Certificate provider" "")"
  cert_domain="$(_prompt_value "Certificate domain" "")"

  healthchecks_json="{}"
  while _prompt_yes_no "Add healthcheck?" "n"; do
    health_name="$(_prompt_value "  Healthcheck name/service" "")"
    health_url="$(_prompt_value "  Healthcheck URL" "")"
    [[ -z "${health_name}" ]] && continue
    healthchecks_json="$(jq --arg name "${health_name}" --arg url "${health_url}" '. + {($name): $url}' <<< "${healthchecks_json}")"
  done

  compose_json="$(jq -Rn --arg raw "${compose_files}" '$raw | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')"
  jq -n \
    --arg host "${host}" \
    --arg user "${user}" \
    --arg path "${path}" \
    --arg ssh_key "${ssh_key}" \
    --arg docker_network "${docker_network}" \
    --arg cert_provider "${cert_provider}" \
    --arg cert_domain "${cert_domain}" \
    --argjson compose_files "${compose_json}" \
    --argjson healthchecks "${healthchecks_json}" \
    '{
      remote: {host: $host, user: $user, path: $path, ssh_key_path: $ssh_key},
      docker: {network: $docker_network, compose_files: $compose_files},
      healthchecks: $healthchecks,
      certificates: {provider: $cert_provider, domain: $cert_domain}
    }'
}

_materialize_project_structure_reference() {
  require_bins jq yq

  local scripts_dir structure_file
  scripts_dir="${OPS_PROJECT_ROOT}/scripts"
  structure_file="${scripts_dir}/project_structure.json"

  mkdir -p "${scripts_dir}"

  local backend_json frontend_json
  local backend_idx frontend_idx
  backend_json='{}'
  frontend_json='{}'
  backend_idx=0
  frontend_idx=0

  local id name path key
  while IFS= read -r id; do
    [[ -z "${id}" || "${id}" == "null" ]] && continue
    name="$(manifest_get_service_field "${id}" name)"
    path="$(manifest_get_service_field "${id}" path)"
    [[ -z "${path}" || "${path}" == "null" ]] && continue
    [[ -z "${name}" || "${name}" == "null" ]] && name="${id}"

    if [[ "${path}" == BACKENDs/* ]]; then
      backend_idx=$((backend_idx + 1))
      key="backend_${backend_idx}"
      backend_json="$(jq \
        --arg key "${key}" \
        --arg name "${name}" \
        --arg folder "${id}" \
        --arg path "${path}" \
        '. + {($key): {name: $name, folder: $folder, path: $path}}' \
        <<< "${backend_json}")"
    elif [[ "${path}" == frontend/* ]]; then
      frontend_idx=$((frontend_idx + 1))
      key="frontend_${frontend_idx}"
      frontend_json="$(jq \
        --arg key "${key}" \
        --arg name "${name}" \
        --arg folder "${id}" \
        --arg path "${path}" \
        '. + {($key): {name: $name, folder: $folder, path: $path}}' \
        <<< "${frontend_json}")"
    fi
  done < <(manifest_list_services)

  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --argjson backend "${backend_json}" \
    --argjson frontend "${frontend_json}" \
    '{
      "$schema": "./schema.json",
      meta: {
        description: "Generated by ops setup from .ops.yaml services.",
        generated_at: $generated_at,
        paths_relative_to: "repository root"
      },
      version: "1.0.0",
      BACKEND: $backend,
      FRONTEND: $frontend
    }' > "${structure_file}"

  ops_ok "Materialized scripts/project_structure.json from .ops.yaml services"
}

_materialize_project_values_metadata() {
  require_bins jq yq

  local scripts_dir values_file tmp_values
  scripts_dir="${OPS_PROJECT_ROOT}/scripts"
  values_file="${scripts_dir}/project_values.json"
  mkdir -p "${scripts_dir}"

  local project_name
  project_name="$(yq e '.project.name // ""' "${OPS_MANIFEST}" 2>/dev/null || true)"
  [[ -z "${project_name}" || "${project_name}" == "null" ]] && project_name="$(basename "${OPS_PROJECT_ROOT}")"

  local stack_mapping_json id stack
  stack_mapping_json='{}'
  while IFS= read -r id; do
    [[ -z "${id}" || "${id}" == "null" ]] && continue
    stack="$(manifest_get_service_field "${id}" stack)"
    [[ -z "${stack}" || "${stack}" == "null" ]] && stack="custom"
    stack_mapping_json="$(jq --arg id "${id}" --arg stack "${stack}" '. + {($id): $stack}' <<< "${stack_mapping_json}")"
  done < <(manifest_list_services)

  if [[ -f "${values_file}" ]]; then
    tmp_values="$(mktemp)"
    jq \
      --arg project_name "${project_name}" \
      --argjson stack_mapping "${stack_mapping_json}" \
      '.project_metadata = (.project_metadata // {})
       | .project_metadata.name = $project_name
       | .project_metadata.stack_mapping = $stack_mapping' \
      "${values_file}" > "${tmp_values}"
    mv "${tmp_values}" "${values_file}"
  else
    jq -n \
      --arg project_name "${project_name}" \
      --argjson stack_mapping "${stack_mapping_json}" \
      '{
        meta: {description: "Generated by ops setup."},
        constants_in_scripts: {},
        project_metadata: {
          name: $project_name,
          stack_mapping: $stack_mapping
        }
      }' > "${values_file}"
  fi

  ops_ok "Materialized scripts/project_values.json project_metadata"
}

_backup_file() {
  local file="$1"
  [[ -f "${file}" ]] || return 0
  local ts dest
  ts="$(ops_timestamp | tr ':' '-')"
  mkdir -p "${OPS_PROJECT_HISTORY_DIR}"
  dest="${OPS_PROJECT_HISTORY_DIR}/$(basename "${file}").${ts}.bak"
  cp "${file}" "${dest}"
  ops_ok "Backed up ${file#${OPS_PROJECT_ROOT}/} -> ${dest#${OPS_PROJECT_ROOT}/}"
}

_apply_generated() {
  local setup_tmp profile_tmp
  require_bins jq yq
  setup_tmp="$(mktemp)"
  profile_tmp="$(mktemp)"
  if [[ "${INTERACTIVE}" == "true" ]]; then
    _interactive_setup_json > "${setup_tmp}"
    _interactive_profile_json > "${profile_tmp}"
  else
    _generate_setup_json > "${setup_tmp}"
    _generate_profile_json "${PROFILE}" > "${profile_tmp}"
  fi

  _backup_file "${OPS_MANIFEST}"
  mkdir -p "${OPS_PROJECT_STATE_DIR}" "${OPS_PROFILES_DIR}" "${OPS_PROJECT_GENERATED_DIR}" "${OPS_PROJECT_LOG_DIR}" "${OPS_PROJECT_RUN_DIR}"
  yq e -i ".setup = load(\"${setup_tmp}\") | .profiles.${PROFILE} = load(\"${profile_tmp}\")" "${OPS_MANIFEST}"
  yq e -P -i '.' "${OPS_MANIFEST}"
  yq e -o=json -I=2 ".setup" "${OPS_MANIFEST}" > "${OPS_PROJECT_GENERATED_DIR}/setup.json"
  yq e -o=json -I=2 ".profiles.${PROFILE}" "${OPS_MANIFEST}" > "$(setup_profile_file "${PROFILE}")"
  rm -f "${OPS_PROJECT_GENERATED_DIR}/setup.yaml" "${OPS_PROFILES_DIR}/${PROFILE}.yaml" >/dev/null 2>&1 || true
  _materialize_project_structure_reference
  _materialize_project_values_metadata
  rm -f "${setup_tmp}" "${profile_tmp}"
  ops_ok "Updated .ops.yaml setup section"
  ops_ok "Updated .ops.yaml profiles.${PROFILE} section"
  ops_ok "Materialized .ops.project/generated/setup.json and .ops.project/profiles/${PROFILE}.json"
}

_show_setup() {
  ops_section "ops setup show"
  printf 'Root config: %s (%s)\n' "${OPS_MANIFEST#${OPS_PROJECT_ROOT}/}" "$([[ -f "${OPS_MANIFEST}" ]] && printf exists || printf missing)"
  printf 'Profile: %s\n' "${PROFILE}"
  printf 'Materialized profile: %s (%s)\n' ".ops.project/profiles/${PROFILE}.json" "$( [[ -f "$(setup_profile_file "${PROFILE}")" ]] && printf exists || printf missing)"
  printf '\n'
  if setup_exists; then
    yq e -P '.setup' "${OPS_MANIFEST}"
  else
    _generate_setup_json
  fi
  printf '\nProfile config\n'
  if [[ "$(yq e ".profiles.${PROFILE} // \"\"" "${OPS_MANIFEST}" 2>/dev/null)" != "" ]]; then
    yq e -P ".profiles.${PROFILE}" "${OPS_MANIFEST}"
  else
    _generate_profile_json "${PROFILE}"
  fi
}

_doctor_setup() {
  local fail=0
  ops_section "ops setup doctor"
  require_bins yq

  if setup_validate; then ops_ok ".ops.yaml setup section valid or not yet generated"; else ops_error ".ops.yaml setup section invalid"; fail=$((fail+1)); fi
  if setup_profile_validate "${PROFILE}"; then ops_ok ".ops.yaml profiles.${PROFILE} valid or not yet generated"; else ops_error ".ops.yaml profiles.${PROFILE} invalid"; fail=$((fail+1)); fi

  local host user path
  host="$(setup_profile_get "${PROFILE}" '.remote.host' '')"
  user="$(setup_profile_get "${PROFILE}" '.remote.user' '')"
  path="$(setup_profile_get "${PROFILE}" '.remote.path' '')"
  if [[ "${PROFILE}" != "local" && ( -z "${host}" || -z "${user}" || -z "${path}" ) ]]; then
    ops_warn "Remote profile '${PROFILE}' has incomplete remote.host/user/path"
  fi

  while IFS= read -r svc; do
    [[ -z "${svc}" ]] && continue
    local svc_path
    svc_path="$(manifest_get_service_field "${svc}" path)"
    if [[ -d "${OPS_PROJECT_ROOT}/${svc_path}" ]]; then
      ops_ok "service path: ${svc} -> ${svc_path}"
    else
      ops_error "missing service path: ${svc} -> ${svc_path}"
      fail=$((fail+1))
    fi
  done < <(manifest_list_services)

  return "${fail}"
}

case "${SUBCMD}" in
  discover)
    _run_discovery
    ;;
  show)
    require_manifest
    _show_setup
    ;;
  doctor)
    require_manifest
    _doctor_setup
    ;;
  generate)
    ops_section "ops setup"
    if ! manifest_exists; then
      ops_warn ".ops.yaml not found. Running discovery-only setup preview."
      _run_discovery
      if [[ "${APPLY}" == "true" ]]; then
        ops_info "Manifest/config generation from discovery is not implemented in this batch yet."
      fi
      exit 0
    fi
    if [[ "${DRY_RUN}" == "true" || "${APPLY}" == "false" ]]; then
      discovery_json="$(discovery_scan_project_json)"
      _print_discovery_preview "${discovery_json}"
      ops_info "Preview root .ops.yaml setup/profile sections for '${PROFILE}'. Use --apply to write."
      printf '\n.ops.yaml setup:\n'
      if [[ "${INTERACTIVE}" == "true" ]]; then
        _interactive_setup_json | yq e -P -
      else
        _generate_setup_json | yq e -P -
      fi
      printf '\n.ops.yaml profiles.%s:\n' "${PROFILE}"
      if [[ "${INTERACTIVE}" == "true" ]]; then
        _interactive_profile_json | yq e -P -
      else
        _generate_profile_json "${PROFILE}" | yq e -P -
      fi
    else
      _apply_generated
    fi
    ;;
  *)
    die "Unknown setup subcommand: ${SUBCMD}" 2
    ;;
esac
