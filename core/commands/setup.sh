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
MODULE=""
EXPLICIT_SETUP_TARGET=false

_usage_setup() {
  cat <<'EOF'
Usage: ops setup
       ops setup [all] [--profile NAME] [--dry-run] [--apply]
       ops setup --module MODULE [--apply]
       ops setup project [--apply]
       ops setup ci [--interactive] [--apply]
       ops setup init [--profile NAME] [--apply]
       ops setup interactive [--profile NAME] [--apply]
       ops setup --interactive [--profile NAME] [--apply]
       ops setup discover [--apply]
       ops setup apply-services [--apply]
       ops setup dependencies [--interactive] [--apply]
       ops setup show [--profile NAME]
       ops setup doctor [--profile NAME]

Setup modules:
  all           Default. Project base + discovery/config/services/dependencies.
  project       Base .ops.project directories and project config only.
  services      Discovery-backed services/config apply path.
  dependencies  Dependency decision preview/interview/apply.
  ci            CI/server local env/config setup.

Generates and validates project setup values:
  .ops.yaml setup/settings/profiles sections
  .ops.project/ generated state directories
  .ops.project/config project memory files
  .ops.project/config/decisions.json interactive/default setup decisions
  .ops.project/generated/discovery.json workspace discovery cache
  .ops.project/generated/project_structure.json and project_values.json metadata

Bare `ops setup` starts an interactive setup sequence when a terminal is
available. In non-interactive shells it previews the full setup plan.
EOF
}

if [[ $# -gt 0 ]]; then
  case "${1}" in
    all|-all|--all)
      EXPLICIT_SETUP_TARGET=true
      SUBCMD="generate"
      shift
      ;;
    project|ci)
      EXPLICIT_SETUP_TARGET=true
      SUBCMD="$1"
      shift
      ;;
    services)
      EXPLICIT_SETUP_TARGET=true
      SUBCMD="apply-services"
      shift
      ;;
    init)
      EXPLICIT_SETUP_TARGET=true
      SUBCMD="generate"
      INTERACTIVE=true
      shift
      ;;
    interactive)
      EXPLICIT_SETUP_TARGET=true
      SUBCMD="wizard"
      INTERACTIVE=true
      shift
      ;;
    discover|apply-services|dependencies|show|doctor|help|--help|-h)
      EXPLICIT_SETUP_TARGET=true
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
    --all|-all) EXPLICIT_SETUP_TARGET=true; SUBCMD="generate" ;;
    --module=*) EXPLICIT_SETUP_TARGET=true; MODULE="${_arg#*=}" ;;
    --module)
      die "--module requires --module=name form for now" 2
      ;;
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

if [[ -n "${MODULE}" ]]; then
  case "${MODULE}" in
    all) SUBCMD="generate" ;;
    project|ci|dependencies) SUBCMD="${MODULE}" ;;
    services) SUBCMD="apply-services" ;;
    *) die "Unknown setup module: ${MODULE}" 2 ;;
  esac
fi

[[ -z "${SUBCMD}" ]] && SUBCMD="generate"
[[ "${SUBCMD}" == "help" || "${SUBCMD}" == "--help" || "${SUBCMD}" == "-h" ]] && { _usage_setup; exit 0; }
[[ -z "${PROFILE}" ]] && PROFILE="$(setup_default_profile)"

if [[ "${EXPLICIT_SETUP_TARGET}" == "false" && "${DRY_RUN}" == "false" && "${INTERACTIVE}" == "true" ]]; then
  SUBCMD="wizard"
fi

if [[ "${EXPLICIT_SETUP_TARGET}" == "false" && "${DRY_RUN}" == "false" && "${APPLY}" == "false" && "${INTERACTIVE}" == "false" && -t 0 ]]; then
  SUBCMD="wizard"
fi

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
    printf '%s [%s]: ' "${label}" "${default}" >&2
    IFS= read -r value || value=""
    printf '%s' "${value:-${default}}"
  else
    printf '%s: ' "${label}" >&2
    IFS= read -r value || value=""
    printf '%s' "${value}"
  fi
}

_prompt_yes_no() {
  local label="$1" default="${2:-n}" value
  printf '%s [%s]: ' "${label}" "${default}" >&2
  IFS= read -r value || value=""
  value="${value:-${default}}"
  case "${value}" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

_setup_wizard_choose() {
  local label="$1" default="${2:-y}"
  _prompt_yes_no "${label}" "${default}"
}

_run_setup_wizard() {
  ops_section "ops setup"
  printf 'Interactive setup sequence\n'
  printf 'Project: %s\n' "${OPS_PROJECT_ROOT}"
  printf 'Profile: %s\n\n' "${PROFILE}"

  local run_project=false run_services=false run_dependencies=false run_ci=false

  if _setup_wizard_choose "Create/update base .ops.project structure?" "y"; then
    run_project=true
  fi
  if _setup_wizard_choose "Discover and apply runtime services/config?" "y"; then
    run_services=true
  fi
  if _setup_wizard_choose "Review service dependencies?" "y"; then
    run_dependencies=true
  fi
  if _setup_wizard_choose "Configure local CI/deploy env and SSH metadata?" "n"; then
    run_ci=true
  fi

  printf '\n'
  if [[ "${DRY_RUN}" == "true" ]]; then
    APPLY=false
    ops_info "Dry run selected. Wizard will preview selected modules."
  elif [[ "${APPLY}" == "true" ]]; then
    ops_info "Apply mode selected from --apply."
  elif _setup_wizard_choose "Apply selected setup modules now?" "y"; then
    APPLY=true
  else
    APPLY=false
  fi
  INTERACTIVE=true

  if [[ "${run_project}" == "true" ]]; then
    _run_project_setup
  fi
  if [[ "${run_services}" == "true" ]]; then
    _run_apply_services
  fi
  if [[ "${run_dependencies}" == "true" ]]; then
    _run_dependencies
  fi
  if [[ "${run_ci}" == "true" ]]; then
    _run_ci_setup_module
  fi

  printf '\n'
  ops_ok "Setup sequence complete"
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

_write_project_gitignore() {
  local file="${OPS_PROJECT_STATE_DIR}/.gitignore"
  mkdir -p "${OPS_PROJECT_STATE_DIR}"
  if [[ ! -f "${file}" ]]; then
    {
      printf '# Generated by ops. .ops.project is local project state.\n'
      printf 'secrets/\n'
      printf 'logs/\n'
      printf 'run/\n'
    } > "${file}"
    ops_ok "Wrote ${file#${OPS_PROJECT_ROOT}/}"
  else
    local changed=false
    for item in 'secrets/' 'logs/' 'run/'; do
      if ! grep -qx "${item}" "${file}" 2>/dev/null; then
        printf '%s\n' "${item}" >> "${file}"
        changed=true
      fi
    done
    [[ "${changed}" == "true" ]] && ops_ok "Updated ${file#${OPS_PROJECT_ROOT}/}"
  fi
  return 0
}

_project_base_json() {
  require_bins jq
  local project_name
  project_name="$(basename "${OPS_PROJECT_ROOT}")"
  if manifest_exists; then
    project_name="$(yq e '.project.name // ""' "${OPS_MANIFEST}" 2>/dev/null || true)"
    [[ -z "${project_name}" || "${project_name}" == "null" ]] && project_name="$(basename "${OPS_PROJECT_ROOT}")"
  elif [[ -f "${OPS_PROJECT_CONFIG_DIR}/project.json" ]]; then
    project_name="$(jq -r '.name // empty' "${OPS_PROJECT_CONFIG_DIR}/project.json" 2>/dev/null || true)"
    [[ -z "${project_name}" ]] && project_name="$(basename "${OPS_PROJECT_ROOT}")"
  fi

  jq -n \
    --arg version "1" \
    --arg generated_at "$(ops_timestamp)" \
    --arg name "${project_name}" \
    --arg root "${OPS_PROJECT_ROOT}" \
    --arg config_dir ".ops.project/config" \
    --arg generated_dir ".ops.project/generated" \
    '{
      version: $version,
      generated_at: $generated_at,
      name: $name,
      root: $root,
      config_dir: $config_dir,
      generated_dir: $generated_dir
    }'
}

_ensure_project_base() {
  mkdir -p "${OPS_PROJECT_STATE_DIR}" "${OPS_PROJECT_CONFIG_DIR}" "${OPS_PROJECT_GENERATED_DIR}" "${OPS_PROJECT_LOG_DIR}" "${OPS_PROJECT_RUN_DIR}" "${OPS_PROFILES_DIR}"
  _write_project_gitignore
  if [[ ! -f "${OPS_PROJECT_CONFIG_DIR}/project.json" ]]; then
    _project_base_json > "${OPS_PROJECT_CONFIG_DIR}/project.json"
    ops_ok "Wrote .ops.project/config/project.json"
  else
    ops_ok "Project base exists: .ops.project"
  fi
}

_run_project_setup() {
  ops_section "ops setup project"
  printf 'Project state dir: %s\n' "${OPS_PROJECT_STATE_DIR#${OPS_PROJECT_ROOT}/}"
  printf 'Config dir: %s\n' "${OPS_PROJECT_CONFIG_DIR#${OPS_PROJECT_ROOT}/}"
  printf 'Generated dir: %s\n' "${OPS_PROJECT_GENERATED_DIR#${OPS_PROJECT_ROOT}/}"
  printf 'Logs dir: %s\n' "${OPS_PROJECT_LOG_DIR#${OPS_PROJECT_ROOT}/}"
  printf 'Run dir: %s\n' "${OPS_PROJECT_RUN_DIR#${OPS_PROJECT_ROOT}/}"
  printf 'Profiles dir: %s\n' "${OPS_PROFILES_DIR#${OPS_PROJECT_ROOT}/}"

  if [[ "${APPLY}" != "true" ]]; then
    printf '\n'
    ops_info "Preview only. Use --apply to create the base .ops.project structure."
    return 0
  fi

  _ensure_project_base
}

_manifest_service_process_exists() {
  local id="$1" name="$2"
  manifest_exists || return 1
  yq e ".services[] | select(.id == \"${id}\") | .run.processes[]?.name" "${OPS_MANIFEST}" 2>/dev/null |
    grep -qFx "${name}"
}

_process_output_default_enabled() {
  local id="$1" name="$2"

  if manifest_exists; then
    if _manifest_service_process_exists "${id}" "${name}"; then
      printf 'true'
    else
      printf 'false'
    fi
    return 0
  fi

  case "${name}" in
    webhook|*webhook*) printf 'false' ;;
    *) printf 'true' ;;
  esac
}

_process_output_is_ambiguous() {
  local id="$1" name="$2"

  case "${name}" in
    webhook|*webhook*) return 0 ;;
  esac

  if manifest_exists && ! _manifest_service_process_exists "${id}" "${name}"; then
    return 0
  fi

  return 1
}

_resolve_process_decisions_json() {
  local discovery_json="$1"
  local decisions_json='[]'
  local process_entries=()

  mapfile -t process_entries < <(jq -r '
    .directories[]
    | select(.service == true and .role == "process_group")
    | .id as $id
    | (.build.outputs // [])[]
    | [$id, .name, .package]
    | @tsv
  ' <<< "${discovery_json}")

  local entry
  for entry in "${process_entries[@]}"; do
    IFS=$'\t' read -r id name package <<< "${entry}"
    [[ -z "${id}" || -z "${name}" ]] && continue
    local default_enabled enabled ambiguous reason
    default_enabled="$(_process_output_default_enabled "${id}" "${name}")"
    enabled="${default_enabled}"
    ambiguous=false
    reason="default"

    if _process_output_is_ambiguous "${id}" "${name}"; then
      ambiguous=true
      reason="ambiguous_process"
      if [[ "${INTERACTIVE}" == "true" ]]; then
        local default_answer="n"
        [[ "${default_enabled}" == "true" ]] && default_answer="y"
        if _prompt_yes_no "Include process '${id}/${name}' in local runtime?" "${default_answer}"; then
          enabled=true
        else
          enabled=false
        fi
        reason="interactive"
      fi
    fi

    decisions_json="$(jq \
      --arg id "${id}" \
      --arg name "${name}" \
      --arg package "${package}" \
      --argjson enabled "${enabled}" \
      --argjson ambiguous "${ambiguous}" \
      --arg reason "${reason}" \
      '. + [{type: "process", service: $id, name: $name, package: $package, enabled: $enabled, ambiguous: $ambiguous, reason: $reason}]' \
      <<< "${decisions_json}")"
  done

  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --argjson decisions "${decisions_json}" \
    '{version: "1", generated_at: $generated_at, decisions: $decisions}'
}

_apply_discovery_decisions_json() {
  local discovery_json="$1" decisions_json="$2"

  jq \
    --argjson decisions "${decisions_json}" \
    '
      .directories |= map(
        if .service == true and .role == "process_group" then
          . as $service
          | .build.outputs = (
              (.build.outputs // [])
              | map(
                  . as $output
                  | ($decisions.decisions[]? | select(.type == "process" and .service == $service.id and .name == $output.name)) as $decision
                  | . + {
                      enabled: (if $decision == null or ($decision | has("enabled") | not) then true else $decision.enabled end),
                      ambiguous: (if $decision == null or ($decision | has("ambiguous") | not) then false else $decision.ambiguous end),
                      decision_reason: ($decision.reason // "default")
                    }
                )
            )
        else
          .
        end
      )
    ' <<< "${discovery_json}"
}

_json_array_to_space() {
  jq -r '(. // []) | join(" ")'
}

_service_dependency_default_json() {
  local service_id="$1"
  local deps_json=""

  if [[ -f "${OPS_PROJECT_CONFIG_SERVICES_FILE:-}" ]]; then
    deps_json="$(jq -c --arg id "${service_id}" '
      (.services[]? | select(.id == $id) | .depends_on) // []
    ' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || true)"
  fi

  if [[ -z "${deps_json}" || "${deps_json}" == "null" ]] && manifest_exists; then
    deps_json="$(yq e -o=json ".services[] | select(.id == \"${service_id}\") | .depends_on // []" "${OPS_MANIFEST}" 2>/dev/null || true)"
  fi

  [[ -n "${deps_json}" && "${deps_json}" != "null" ]] && printf '%s' "${deps_json}" || printf '[]'
}

_dependency_reply_to_json() {
  local reply="$1" service_id="$2" valid_ids="$3"
  local deps_json="[]"
  local dep

  for dep in ${reply}; do
    [[ -z "${dep}" ]] && continue
    if [[ "${dep}" == "${service_id}" ]]; then
      printf 'Service %s cannot depend on itself.\n' "${service_id}" >&2
      return 1
    fi
    if ! printf ' %s ' "${valid_ids}" | grep -qF " ${dep} "; then
      printf "Unknown dependency '%s'. Valid service ids: %s\n" "${dep}" "${valid_ids}" >&2
      return 1
    fi
    deps_json="$(jq -c --arg dep "${dep}" 'if index($dep) then . else . + [$dep] end' <<< "${deps_json}")"
  done

  printf '%s' "${deps_json}"
}

_dependency_prompt_value() {
  local label="$1" default="${2:-}" value
  if [[ -n "${default}" ]]; then
    printf '%s [%s]: ' "${label}" "${default}" >&2
  else
    printf '%s: ' "${label}" >&2
  fi
  read -r value
  printf '%s' "${value:-${default}}"
}

_resolve_dependency_decisions_json() {
  local discovery_json="$1" decisions_json="$2"
  local valid_ids dependency_decisions="[]"
  local service_entries=()

  valid_ids="$(jq -r '[.directories[] | select(.service == true) | .id] | join(" ")' <<< "${discovery_json}")"

  mapfile -t service_entries < <(jq -r '
    .directories[]
    | select(.service == true)
    | [.id, .path, .role]
    | @tsv
  ' <<< "${discovery_json}")

  local entry
  for entry in "${service_entries[@]}"; do
    IFS=$'\t' read -r id path role <<< "${entry}"
    [[ -z "${id}" || "${id}" == "null" ]] && continue
    local default_deps default_text deps_json reason confirmed reply

    default_deps="$(_service_dependency_default_json "${id}")"
    default_text="$(_json_array_to_space <<< "${default_deps}")"
    deps_json="${default_deps}"
    reason="default"
    confirmed=false

    if [[ -n "${default_text}" ]]; then
      reason="preserved"
    fi

    if [[ "${INTERACTIVE}" == "true" ]]; then
      while true; do
        reply="$(_dependency_prompt_value "Dependencies for '${id}' (valid: ${valid_ids}; space-separated)" "${default_text}")"
        if deps_json="$(_dependency_reply_to_json "${reply}" "${id}" "${valid_ids}")"; then
          break
        fi
      done
      reason="interactive"
      confirmed=true
    fi

    dependency_decisions="$(jq \
      --arg id "${id}" \
      --arg path "${path}" \
      --arg role "${role}" \
      --arg reason "${reason}" \
      --argjson confirmed "${confirmed}" \
      --argjson dependencies "${deps_json}" \
      '. + [{type: "dependency", service: $id, path: $path, role: $role, dependencies: $dependencies, confirmed: $confirmed, reason: $reason}]' \
      <<< "${dependency_decisions}")"
  done

  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --argjson existing "${decisions_json}" \
    --argjson dependency_decisions "${dependency_decisions}" \
    '{
      version: "1",
      generated_at: $generated_at,
      decisions: ((($existing.decisions // []) | map(select(.type != "dependency"))) + $dependency_decisions)
    }'
}

_resolve_setup_decisions_json() {
  local discovery_json="$1"
  local decisions_json

  decisions_json="$(_resolve_process_decisions_json "${discovery_json}")"
  _resolve_dependency_decisions_json "${discovery_json}" "${decisions_json}"
}

_discovery_human_name() {
  local id="$1"
  awk -v value="${id}" 'BEGIN {
    n = split(value, parts, /[_-]+/)
    first = 1
    for (i = 1; i <= n; i++) {
      part = parts[i]
      if (part == "") continue
      if (!first) printf " "
      printf "%s%s", toupper(substr(part, 1, 1)), tolower(substr(part, 2))
      first = 0
    }
  }'
}

_discovery_services_yaml() {
  local discovery_json="$1"

  jq -c '.directories[] | select(.service == true)' <<< "${discovery_json}" |
    while IFS= read -r entry; do
      local id name stack path role
      id="$(jq -r '.id' <<< "${entry}")"
      name="$(_discovery_human_name "${id}")"
      stack="$(jq -r '.stack' <<< "${entry}")"
      path="$(jq -r '.path' <<< "${entry}")"
      role="$(jq -r '.role' <<< "${entry}")"

      printf '  - id: %s\n' "${id}"
      printf '    name: "%s"\n' "${name}"
      printf '    stack: %s\n' "${stack}"
      printf '    path: %s\n' "${path}"
      printf '    env_files: []\n'
      printf '    env_policy: dev_file\n'
      printf '    env_materialization: none\n'
      printf '    env_output_file: ""\n'
      printf '    actions:\n'
      printf '      start: ""\n'
      printf '      stop: ""\n'
      printf '      logs: ""\n'
      printf '      build: ""\n'
      printf '      test: ""\n'
      printf '      lint: ""\n'
      printf '    depends_on: []\n'
      printf '    healthcheck: ""\n'

      if [[ "${role}" == "process_group" ]]; then
        printf '    runner:\n'
        printf '      kind: process_group\n'
        printf '    build:\n'
        printf '      output_dir: .ops.project/generated/bin/%s\n' "${id}"
        printf '      target_os: linux\n'
        printf '      target_arch: amd64\n'
        printf '      outputs:\n'
        jq -r '.build.outputs[]? | select(.enabled != false) | [.name, .package] | @tsv' <<< "${entry}" |
          while IFS=$'\t' read -r out_name package; do
            printf '        - name: %s\n' "${out_name}"
            printf '          package: %s\n' "${package}"
          done
        printf '    run:\n'
        printf '      processes:\n'
        jq -r '.build.outputs[]? | select(.enabled != false) | .name' <<< "${entry}" |
          while IFS= read -r proc; do
            [[ -n "${proc}" && "${proc}" != "null" ]] && printf '        - name: %s\n' "${proc}"
          done
      fi

      printf '    meta:\n'
      printf '      source: setup_discovery\n'
      printf '      role: %s\n' "${role}"
      printf '      confirmed_by_user: false\n'
      printf '      generated_at: "%s"\n' "$(ops_timestamp)"
      printf '\n'
    done
}

_discovery_start_command() {
  local entry="$1"
  local stack role scripts
  stack="$(jq -r '.stack' <<< "${entry}")"
  role="$(jq -r '.role' <<< "${entry}")"

  if [[ "${role}" == "process_group" ]]; then
    printf ''
    return 0
  fi

  case "${stack}" in
    django) printf 'python -u manage.py runserver 0.0.0.0:8000' ;;
    elixir-phoenix) printf 'mix phx.server' ;;
    go) printf 'go run main.go' ;;
    node)
      scripts="$(jq -c '.package.scripts // {}' <<< "${entry}")"
      if jq -e '.dev?' <<< "${scripts}" >/dev/null 2>&1; then
        printf 'npm run dev'
      elif jq -e '.start?' <<< "${scripts}" >/dev/null 2>&1; then
        printf 'npm start'
      else
        printf ''
      fi
      ;;
    *) printf '' ;;
  esac
}

_generate_setup_json_from_discovery() {
  local discovery_json="$1"
  local services_json="{}"

  while IFS= read -r entry; do
    [[ -z "${entry}" ]] && continue
    local id stack role cmd port service_entry
    id="$(jq -r '.id' <<< "${entry}")"
    stack="$(jq -r '.stack' <<< "${entry}")"
    role="$(jq -r '.role' <<< "${entry}")"
    cmd="$(_discovery_start_command "${entry}")"
    port="0"

    service_entry="$(jq -n \
      --arg runtime "" \
      --arg command "${cmd}" \
      --arg role "${role}" \
      --argjson port "${port}" \
      '{runtime: $runtime, port: $port, command: $command, env_files: [], role: $role}')"
    if [[ "${stack}" == "django" ]]; then
      service_entry="$(jq '. + {django: {conda_env: ""}}' <<< "${service_entry}")"
    fi

    services_json="$(jq \
      --arg id "${id}" \
      --argjson entry "${service_entry}" \
      '. + {($id): $entry}' \
      <<< "${services_json}")"
  done < <(jq -c '.directories[] | select(.service == true)' <<< "${discovery_json}")

  local proposed_json
  proposed_json="$(jq -n \
    --argjson services "${services_json}" \
    '{
      default_profile: "",
      scaffold: {type: "", package_manager: "", template: ""},
      runtimes: {python: {manager: "", env: "", fallbacks: []}},
      services: $services
    }')"

  if manifest_exists; then
    local existing_json
    existing_json="$(yq e -o=json '.setup // {}' "${OPS_MANIFEST}" 2>/dev/null || printf '{}')"
    jq -n \
      --argjson proposed "${proposed_json}" \
      --argjson existing "${existing_json}" \
      '
        $proposed
        | .default_profile = ($existing.default_profile // .default_profile)
        | .scaffold = ($existing.scaffold // .scaffold)
        | .runtimes = ($existing.runtimes // .runtimes)
        | .services = (
            reduce (.services | keys[]) as $id
              ({};
               .[$id] = (
                 ($proposed.services[$id] * ($existing.services[$id] // {}))
                 | .command = $proposed.services[$id].command
                 | .role = $proposed.services[$id].role
               ))
          )
      '
  else
    printf '%s\n' "${proposed_json}"
  fi
}

_generate_project_config_json_from_discovery() {
  local discovery_json="$1"
  local project_name

  project_name="$(basename "${OPS_PROJECT_ROOT}")"
  if manifest_exists; then
    project_name="$(yq e '.project.name // ""' "${OPS_MANIFEST}" 2>/dev/null || true)"
    [[ -z "${project_name}" || "${project_name}" == "null" ]] && project_name="$(basename "${OPS_PROJECT_ROOT}")"
  fi

  jq -n \
    --arg version "1" \
    --arg generated_at "$(ops_timestamp)" \
    --arg name "${project_name}" \
    --arg root "${OPS_PROJECT_ROOT}" \
    --arg manifest ".ops.yaml" \
    --arg discovery ".ops.project/generated/discovery.json" \
    '{
      version: $version,
      generated_at: $generated_at,
      name: $name,
      root: $root,
      compatibility_manifest: $manifest,
      discovery_cache: $discovery
    }'
}

_default_settings_json() {
  jq -n '{
    run: {default_mode: "foreground"},
    start: {mode: "foreground", with_deps: true, preview: {enabled: true, lines: 20, wait_seconds: 1}}
  }'
}

_generate_services_config_json_from_discovery() {
  local discovery_json="$1" setup_json="$2" decisions_json="${3:-}"
  local existing_services_json="[]"

  if manifest_exists; then
    existing_services_json="$(yq e -o=json '.services // []' "${OPS_MANIFEST}" 2>/dev/null || printf '[]')"
  elif project_config_services_exists; then
    existing_services_json="$(jq -c '.services // []' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || printf '[]')"
  fi
  [[ -n "${existing_services_json}" && "${existing_services_json}" != "null" ]] || existing_services_json="[]"
  [[ -n "${decisions_json}" ]] || decisions_json='{"decisions":[]}'

  jq \
    --arg generated_at "$(ops_timestamp)" \
    --argjson setup "${setup_json}" \
    --argjson existing_services "${existing_services_json}" \
    --argjson decisions "${decisions_json}" \
    '{
      version: "1",
      generated_at: $generated_at,
      source: "setup_discovery",
      services: [
        .directories[]
        | select(.service == true)
        | . as $directory
        | {
            id,
            name: (($existing_services[]? | select(.id == $directory.id) | .name) // (.id | gsub("[_-]+"; " ") | split(" ") | map((.[0:1] | ascii_upcase) + .[1:]) | join(" "))),
            stack,
            path,
            role,
            confidence,
            evidence,
            runner: (($existing_services[]? | select(.id == $directory.id) | .runner) // (if .role == "process_group" then {kind: "process_group"} else {kind: "stack"} end)),
            build: (($existing_services[]? | select(.id == $directory.id) | .build) // (.build // {} | .outputs = ((.outputs // []) | map(select(.enabled != false) | {name, package})))),
            run: (($existing_services[]? | select(.id == $directory.id) | .run) // (if .role == "process_group" then {processes: ((.build.outputs // []) | map(select(.enabled != false) | {name}))} else {} end)),
            actions: (($existing_services[]? | select(.id == $directory.id) | .actions) // {}),
            env_files: (($existing_services[]? | select(.id == $directory.id) | .env_files) // []),
            env_policy: (($existing_services[]? | select(.id == $directory.id) | .env_policy) // ""),
            env_materialization: (($existing_services[]? | select(.id == $directory.id) | .env_materialization) // ""),
            env_output_file: (($existing_services[]? | select(.id == $directory.id) | .env_output_file) // ""),
            depends_on: (($decisions.decisions[]? | select(.type == "dependency" and .service == $directory.id) | .dependencies) // (($existing_services[]? | select(.id == $directory.id) | .depends_on) // [])),
            healthcheck: (($existing_services[]? | select(.id == $directory.id) | .healthcheck) // ""),
            setup: {
              command: ($setup.services[.id].command // ""),
              env_files: ($setup.services[.id].env_files // []),
              port: ($setup.services[.id].port // 0),
              runtime: ($setup.services[.id].runtime // "")
            },
            meta: {
              source: "setup_discovery",
              confirmed_by_user: false
            }
          }
      ]
    }' <<< "${discovery_json}"
}

_materialize_project_config_from_discovery() {
  local discovery_json="$1" setup_json="$2" profile_json="$3" decisions_json="${4:-}"
  local settings_json="{}" services_tmp

  mkdir -p "${OPS_PROJECT_CONFIG_DIR}"
  if manifest_exists; then
    settings_json="$(yq e -o=json '.settings // {}' "${OPS_MANIFEST}" 2>/dev/null || printf '{}')"
  else
    settings_json="$(_default_settings_json)"
  fi

  _generate_project_config_json_from_discovery "${discovery_json}" > "${OPS_PROJECT_CONFIG_DIR}/project.json"
  services_tmp="$(mktemp)"
  _generate_services_config_json_from_discovery "${discovery_json}" "${setup_json}" "${decisions_json}" > "${services_tmp}"
  mv "${services_tmp}" "${OPS_PROJECT_CONFIG_DIR}/services.json"
  if [[ -n "${decisions_json}" ]]; then
    printf '%s\n' "${decisions_json}" > "${OPS_PROJECT_CONFIG_DIR}/decisions.json"
  fi
  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --arg source "setup_discovery" \
    --argjson settings "${settings_json}" \
    --argjson setup "${setup_json}" \
    '{version: "1", generated_at: $generated_at, source: $source, settings: $settings, setup: $setup}' \
    > "${OPS_PROJECT_CONFIG_DIR}/settings.json"
  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --arg profile "${PROFILE}" \
    --argjson profile_config "${profile_json}" \
    '{version: "1", generated_at: $generated_at, default_profile: $profile, profiles: {($profile): $profile_config}}' \
    > "${OPS_PROJECT_CONFIG_DIR}/profiles.json"

  ops_ok "Materialized .ops.project/config/project.json"
  ops_ok "Materialized .ops.project/config/services.json"
  [[ -n "${decisions_json}" ]] && ops_ok "Materialized .ops.project/config/decisions.json"
  ops_ok "Materialized .ops.project/config/settings.json"
  ops_ok "Materialized .ops.project/config/profiles.json"
}

_generate_manifest_json_from_discovery() {
  local discovery_json="$1" setup_json="$2" profile_json="$3" decisions_json="${4:-}"
  local project_name settings_json services_config

  project_name="$(basename "${OPS_PROJECT_ROOT}")"
  settings_json="$(_default_settings_json)"
  services_config="$(_generate_services_config_json_from_discovery "${discovery_json}" "${setup_json}" "${decisions_json}")"

  jq -n \
    --arg project_name "${project_name}" \
    --arg profile "${PROFILE}" \
    --arg generated_at "$(ops_timestamp)" \
    --argjson settings "${settings_json}" \
    --argjson setup "${setup_json}" \
    --argjson profile_config "${profile_json}" \
    --argjson services_config "${services_config}" \
    '{
      version: "1",
      project: {
        name: $project_name,
        global_env_files: [],
        defaults: {env_policy: "dev_file"}
      },
      services: ($services_config.services | map(
        {
          id,
          name,
          stack,
          path,
          env_files: (.env_files // []),
          env_policy: ((.env_policy // "") | if . == "" then "dev_file" else . end),
          env_materialization: ((.env_materialization // "") | if . == "" then "none" else . end),
          env_output_file: (.env_output_file // ""),
          actions: ((.actions // {}) + {start: (.actions.start // ""), stop: (.actions.stop // ""), logs: (.actions.logs // ""), build: (.actions.build // ""), test: (.actions.test // ""), lint: (.actions.lint // "")}),
          depends_on: (.depends_on // []),
          healthcheck: (.healthcheck // ""),
          meta: {
            source: "setup_discovery",
            role: .role,
            confirmed_by_user: false,
            generated_at: $generated_at
          }
        }
        + (if .runner.kind == "process_group" then {runner: .runner, build: .build, run: .run} else {} end)
      )),
      settings: $settings,
      setup: $setup,
      profiles: {($profile): $profile_config}
    }'
}

_manifest_services_json_from_config() {
  local services_config="$1"

  jq \
    --arg generated_at "$(ops_timestamp)" \
    '
      .services
      | map(
          {
            id,
            name,
            stack,
            path,
            env_files: (.env_files // []),
            env_policy: ((.env_policy // "") | if . == "" then "dev_file" else . end),
            env_materialization: ((.env_materialization // "") | if . == "" then "none" else . end),
            env_output_file: (.env_output_file // ""),
            actions: ((.actions // {}) + {
              start: (.actions.start // ""),
              stop: (.actions.stop // ""),
              logs: (.actions.logs // ""),
              build: (.actions.build // ""),
              test: (.actions.test // ""),
              lint: (.actions.lint // "")
            }),
            depends_on: (.depends_on // []),
            healthcheck: (.healthcheck // ""),
            meta: {
              source: "setup_discovery",
              role: .role,
              confirmed_by_user: false,
              generated_at: $generated_at
            }
          }
          + (if .runner.kind == "process_group" then {runner: .runner, build: .build, run: .run} else {} end)
        )
    ' <<< "${services_config}"
}

_write_manifest_from_discovery() {
  local discovery_json="$1" setup_json="$2" profile_json="$3" decisions_json="${4:-}"

  _generate_manifest_json_from_discovery "${discovery_json}" "${setup_json}" "${profile_json}" "${decisions_json}" |
    yq e -P - > "${OPS_MANIFEST}"
  ops_ok "Created .ops.yaml from discovery"
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

  printf '\nAmbiguous Runtime Decisions\n'
  local decision_lines
  decision_lines="$(jq -r '
    .directories[]
    | select(.service == true and .role == "process_group")
    | .id as $id
    | (.build.outputs // [])[]
    | select(.ambiguous == true or .enabled == false)
    | [$id, .name, (if .enabled == false then "disabled" else "enabled" end), (.decision_reason // "default")]
    | @tsv
  ' <<< "${discovery_json}")"
  if [[ -n "${decision_lines}" ]]; then
    printf '%s\n' "${decision_lines}" |
    while IFS=$'\t' read -r id name state reason; do
      printf '  ? %-14s %-18s %-9s %s\n' "${id}" "${name}" "${state}" "${reason}"
    done
  else
    printf '  none\n'
  fi
}

_print_dependency_decisions_preview() {
  local decisions_json="$1"

  printf '\nDependency Decisions\n'
  local lines
  lines="$(jq -r '
    (.decisions // [])
    | map(select(.type == "dependency"))
    | .[]
    | [.service, (((.dependencies // []) | join(", ")) | if . == "" then "<none>" else . end), (.reason // "default"), ((.confirmed // false) | tostring)]
    | @tsv
  ' <<< "${decisions_json}")"
  if [[ -n "${lines}" ]]; then
    printf '%s\n' "${lines}" |
      while IFS=$'\t' read -r service deps reason confirmed; do
        printf '  %-14s depends_on: %-24s reason=%s confirmed=%s\n' "${service}" "${deps}" "${reason}" "${confirmed}"
      done
  else
    printf '  none\n'
  fi
}

_run_discovery() {
  require_bins jq
  local discovery_json decisions_json discovery_file

  ops_section "ops setup discover"
  discovery_json="$(discovery_scan_project_json)"
  decisions_json="$(_resolve_setup_decisions_json "${discovery_json}")"
  discovery_json="$(_apply_discovery_decisions_json "${discovery_json}" "${decisions_json}")"
  _print_discovery_preview "${discovery_json}"
  _print_dependency_decisions_preview "${decisions_json}"

  if [[ "${APPLY}" == "true" ]]; then
    ensure_dir "${OPS_PROJECT_STATE_DIR}"
    ensure_dir "${OPS_PROJECT_GENERATED_DIR}"
    printf '%s\n' "${discovery_json}" > "${OPS_DISCOVERY_FILE}"
    discovery_file="${OPS_DISCOVERY_FILE}"
    printf '\n'
    ops_ok "Wrote ${discovery_file#${OPS_PROJECT_ROOT}/}"
  else
    printf '\n'
    ops_info "Preview only. Use --apply to write .ops.project/generated/discovery.json."
  fi
}

_print_discovery_config_proposal() {
  local discovery_json="$1"

  printf '\nProposed .ops.yaml services from discovery:\n'
  printf 'services:\n'
  _discovery_services_yaml "${discovery_json}"

  printf '\nProposed .ops.yaml setup from discovery:\n'
  _generate_setup_json_from_discovery "${discovery_json}" | yq e -P -
}

_print_service_merge_summary() {
  local services_json="$1"

  printf '\nCurrent manifest services:\n'
  if manifest_exists; then
    yq e -r '.services[].id' "${OPS_MANIFEST}" 2>/dev/null |
      while IFS= read -r id; do
        [[ -n "${id}" && "${id}" != "null" ]] && printf '  - %s\n' "${id}"
      done
  else
    printf '  none\n'
  fi

  printf '\nProposed runtime services:\n'
  jq -r '.[].id' <<< "${services_json}" |
    while IFS= read -r id; do
      [[ -n "${id}" && "${id}" != "null" ]] && printf '  + %s\n' "${id}"
    done

  printf '\nRemoved from runtime services:\n'
  local removed
  removed="$(jq -r -n \
    --argjson current "$(yq e -o=json '[.services[].id] // []' "${OPS_MANIFEST}" 2>/dev/null || printf '[]')" \
    --argjson proposed "$(jq '[.[].id]' <<< "${services_json}")" \
    '$current - $proposed | .[]?' 2>/dev/null || true)"
  if [[ -n "${removed}" ]]; then
    printf '%s\n' "${removed}" | while IFS= read -r id; do printf '  - %s\n' "${id}"; done
  else
    printf '  none\n'
  fi
}

_run_apply_services() {
  require_bins jq yq
  require_manifest

  local discovery_json decisions_json setup_json profile_json services_config services_json services_tmp

  ops_section "ops setup apply-services"
  discovery_json="$(discovery_scan_project_json)"
  decisions_json="$(_resolve_setup_decisions_json "${discovery_json}")"
  discovery_json="$(_apply_discovery_decisions_json "${discovery_json}" "${decisions_json}")"
  setup_json="$(_generate_setup_json_from_discovery "${discovery_json}")"
  profile_json="$(_generate_profile_json "${PROFILE}")"
  services_config="$(_generate_services_config_json_from_discovery "${discovery_json}" "${setup_json}")"
  services_json="$(_manifest_services_json_from_config "${services_config}")"

  _print_discovery_preview "${discovery_json}"
  _print_dependency_decisions_preview "${decisions_json}"
  _print_service_merge_summary "${services_json}"

  printf '\nProposed .ops.yaml services:\n'
  yq e -P - <<< "${services_json}"

  if [[ "${APPLY}" != "true" ]]; then
    printf '\n'
    ops_info "Preview only. Use --apply to replace .ops.yaml services with discovered runtime services."
    return 0
  fi

  services_tmp="$(mktemp)"
  printf '%s\n' "${services_json}" > "${services_tmp}"
  _backup_file "${OPS_MANIFEST}"
  yq e -i ".services = load(\"${services_tmp}\")" "${OPS_MANIFEST}"
  yq e -P -i '.' "${OPS_MANIFEST}"
  rm -f "${services_tmp}"

  _ensure_project_base
  printf '%s\n' "${discovery_json}" > "${OPS_DISCOVERY_FILE}"
  _materialize_project_config_from_discovery "${discovery_json}" "${setup_json}" "${profile_json}" "${decisions_json}"
  printf '%s\n' "${setup_json}" > "${OPS_PROJECT_GENERATED_DIR}/setup.json"
  printf '%s\n' "${profile_json}" > "$(setup_profile_file "${PROFILE}")"
  _materialize_project_structure_reference
  _materialize_project_values_metadata

  ops_ok "Updated .ops.yaml services from discovery"
}

_run_dependencies() {
  require_bins jq yq

  local discovery_json decisions_json setup_json profile_json services_config

  ops_section "ops setup dependencies"
  [[ "${APPLY}" == "true" ]] && _ensure_project_base
  discovery_json="$(discovery_scan_project_json)"
  decisions_json="$(_resolve_setup_decisions_json "${discovery_json}")"
  discovery_json="$(_apply_discovery_decisions_json "${discovery_json}" "${decisions_json}")"
  setup_json="$(_generate_setup_json_from_discovery "${discovery_json}")"
  profile_json="$(_generate_profile_json "${PROFILE}")"
  services_config="$(_generate_services_config_json_from_discovery "${discovery_json}" "${setup_json}" "${decisions_json}")"

  _print_dependency_decisions_preview "${decisions_json}"

  if [[ "${APPLY}" != "true" ]]; then
    printf '\n'
    ops_info "Preview only. Use --interactive to answer dependency prompts and --apply to write .ops.project/config."
    return 0
  fi

  _ensure_project_base
  printf '%s\n' "${discovery_json}" > "${OPS_DISCOVERY_FILE}"
  _materialize_project_config_from_discovery "${discovery_json}" "${setup_json}" "${profile_json}" "${decisions_json}"
  printf '%s\n' "${setup_json}" > "${OPS_PROJECT_GENERATED_DIR}/setup.json"
  printf '%s\n' "${profile_json}" > "$(setup_profile_file "${PROFILE}")"

  ops_ok "Updated dependency decisions in .ops.project/config/decisions.json"
  ops_ok "Updated service dependencies in .ops.project/config/services.json"
}

_run_ci_setup_module() {
  ops_section "ops setup ci"
  if [[ "${APPLY}" == "true" ]]; then
    _ensure_project_base
  fi

  local args=(setup)
  [[ "${INTERACTIVE}" == "true" ]] && args+=(--interactive)
  [[ "${APPLY}" == "true" ]] && args+=(--apply)
  [[ -n "${PROFILE}" ]] && args+=(--profile "${PROFILE}")
  bash "${_SELF_DIR}/ci.sh" "${args[@]}"

  if [[ "${APPLY}" == "true" ]]; then
    bash "${_SELF_DIR}/ci.sh" env --apply
  else
    ops_info "CI env template is a separate local file. Preview with: ops ci env"
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

  local structure_file
  structure_file="${OPS_PROJECT_GENERATED_DIR}/project_structure.json"

  mkdir -p "${OPS_PROJECT_GENERATED_DIR}"

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

    ops_ok "Materialized .ops.project/generated/project_structure.json from .ops.yaml services"
}

_materialize_project_values_metadata() {
  require_bins jq yq

  local values_file tmp_values
  values_file="${OPS_PROJECT_GENERATED_DIR}/project_values.json"
  mkdir -p "${OPS_PROJECT_GENERATED_DIR}"

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

  ops_ok "Materialized .ops.project/generated/project_values.json project_metadata"
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
  local setup_tmp profile_tmp discovery_tmp decisions_tmp discovery_file had_manifest=false
  require_bins jq yq
  setup_tmp="$(mktemp)"
  profile_tmp="$(mktemp)"
  discovery_tmp="$(mktemp)"
  decisions_tmp="$(mktemp)"
  manifest_exists && had_manifest=true

  if [[ "${INTERACTIVE}" == "true" ]]; then
    discovery_scan_project_json > "${discovery_tmp}"
    _resolve_setup_decisions_json "$(cat "${discovery_tmp}")" > "${decisions_tmp}"
    _apply_discovery_decisions_json "$(cat "${discovery_tmp}")" "$(cat "${decisions_tmp}")" > "${discovery_tmp}.decided"
    mv "${discovery_tmp}.decided" "${discovery_tmp}"
    if [[ "${had_manifest}" == "true" ]]; then
      _interactive_setup_json > "${setup_tmp}"
      _interactive_profile_json > "${profile_tmp}"
    else
      _generate_setup_json_from_discovery "$(cat "${discovery_tmp}")" > "${setup_tmp}"
      _generate_profile_json "${PROFILE}" > "${profile_tmp}"
    fi
  else
    discovery_scan_project_json > "${discovery_tmp}"
    _resolve_setup_decisions_json "$(cat "${discovery_tmp}")" > "${decisions_tmp}"
    _apply_discovery_decisions_json "$(cat "${discovery_tmp}")" "$(cat "${decisions_tmp}")" > "${discovery_tmp}.decided"
    mv "${discovery_tmp}.decided" "${discovery_tmp}"
    _generate_setup_json_from_discovery "$(cat "${discovery_tmp}")" > "${setup_tmp}"
    _generate_profile_json "${PROFILE}" > "${profile_tmp}"
  fi

  _backup_file "${OPS_MANIFEST}"
  _ensure_project_base
  if [[ -s "${discovery_tmp}" ]]; then
    printf '%s\n' "$(cat "${discovery_tmp}")" > "${OPS_DISCOVERY_FILE}"
    discovery_file="${OPS_DISCOVERY_FILE}"
    _materialize_project_config_from_discovery "$(cat "${discovery_tmp}")" "$(cat "${setup_tmp}")" "$(cat "${profile_tmp}")" "$(cat "${decisions_tmp}")"
    ops_ok "Wrote ${discovery_file#${OPS_PROJECT_ROOT}/}"
  fi
  if [[ "${had_manifest}" == "true" ]]; then
    yq e -i ".setup = load(\"${setup_tmp}\") | .profiles.${PROFILE} = load(\"${profile_tmp}\")" "${OPS_MANIFEST}"
    yq e -P -i '.' "${OPS_MANIFEST}"
    yq e -o=json -I=2 ".setup" "${OPS_MANIFEST}" > "${OPS_PROJECT_GENERATED_DIR}/setup.json"
    yq e -o=json -I=2 ".profiles.${PROFILE}" "${OPS_MANIFEST}" > "$(setup_profile_file "${PROFILE}")"
    ops_ok "Updated .ops.yaml setup section"
    ops_ok "Updated .ops.yaml profiles.${PROFILE} section"
  else
    _write_manifest_from_discovery "$(cat "${discovery_tmp}")" "$(cat "${setup_tmp}")" "$(cat "${profile_tmp}")" "$(cat "${decisions_tmp}")"
    cp "${setup_tmp}" "${OPS_PROJECT_GENERATED_DIR}/setup.json"
    cp "${profile_tmp}" "$(setup_profile_file "${PROFILE}")"
  fi
  rm -f "${OPS_PROJECT_GENERATED_DIR}/setup.yaml" "${OPS_PROFILES_DIR}/${PROFILE}.yaml" >/dev/null 2>&1 || true
  _materialize_project_structure_reference
  _materialize_project_values_metadata
  rm -f "${setup_tmp}" "${profile_tmp}" "${discovery_tmp}" "${decisions_tmp}" "${discovery_tmp}.decided"
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
  wizard)
    _run_setup_wizard
    ;;
  project)
    _run_project_setup
    ;;
  ci)
    _run_ci_setup_module
    ;;
  discover)
    _run_discovery
    ;;
  apply-services)
    _run_apply_services
    ;;
  dependencies)
    _run_dependencies
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
      ops_warn ".ops.yaml not found. Running discovery-driven setup."
      discovery_json="$(discovery_scan_project_json)"
      decisions_json="$(_resolve_setup_decisions_json "${discovery_json}")"
      discovery_json="$(_apply_discovery_decisions_json "${discovery_json}" "${decisions_json}")"
      _print_discovery_preview "${discovery_json}"
      _print_dependency_decisions_preview "${decisions_json}"
      _print_discovery_config_proposal "${discovery_json}"
      if [[ "${APPLY}" == "true" ]]; then
        _apply_generated
      else
        ops_info "Preview only. Use --apply to create .ops.project/config and transitional .ops.yaml."
      fi
      exit 0
    fi
    if [[ "${DRY_RUN}" == "true" || "${APPLY}" == "false" ]]; then
      discovery_json="$(discovery_scan_project_json)"
      decisions_json="$(_resolve_setup_decisions_json "${discovery_json}")"
      discovery_json="$(_apply_discovery_decisions_json "${discovery_json}" "${decisions_json}")"
      _print_discovery_preview "${discovery_json}"
      _print_dependency_decisions_preview "${decisions_json}"
      _print_discovery_config_proposal "${discovery_json}"
      ops_info "Preview only. Use --apply to write discovery-backed setup/config."
    else
      _apply_generated
    fi
    ;;
  *)
    die "Unknown setup subcommand: ${SUBCMD}" 2
    ;;
esac
