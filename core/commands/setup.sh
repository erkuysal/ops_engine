#!/usr/bin/env bash
# .ops/core/commands/setup.sh — Project setup generation, inspection, and checks.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/settings.sh"
source "${_SELF_DIR}/../lib/setup.sh"
source "${_SELF_DIR}/../lib/discovery.sh"
source "${_SELF_DIR}/../lib/backup.sh"
source "${_SELF_DIR}/../lib/setup_check.sh"
source "${_SELF_DIR}/../lib/runner.sh"
source "${_SELF_DIR}/../lib/run_plan.sh"

SUBCMD=""
PROFILE=""
DRY_RUN=false
APPLY=false
INTERACTIVE=false
EXPORT_YAML=false
CONFIRM_INFERRED=false
JSON_OUTPUT=false
REFRESH=false
MODULE=""
EXPLICIT_SETUP_TARGET=false
RUN_PLAN_ACTIONS=""
GLOBAL_CI_PROFILE=""
DEFER_CI_CONNECTION=false

_usage_setup() {
  cat <<'EOF'
Usage: ops setup
       ops setup [all] [--profile NAME] [--dry-run] [--apply] [--export-yaml] [--confirm-inferred]
       ops setup --module MODULE [--apply]
       ops setup project [--apply]
       ops setup ci [--interactive] [--global-profile NAME] [--defer-connection] [--apply]
       ops setup init [--profile NAME] [--apply]
       ops setup interactive [--profile NAME] [--apply]
       ops setup --interactive [--profile NAME] [--apply]
       ops setup discover [--apply]
       ops setup apply-services [--apply]
       ops setup dependencies [--interactive] [--apply]
       ops setup shipping [--interactive] [--refresh] [--apply] [--json]
       ops setup run-plans [--apply] [--action=ACTION] [--actions=a,b]
       ops setup export-yaml [--apply]
       ops setup import-yaml [--apply]
       ops setup show [--profile NAME]
       ops setup check [--json]
       ops setup doctor [--profile NAME]
       ops setup --check [--json]

Setup modules:
  all           Default. Project base + discovery/config/services/dependencies.
  project       Base .ops.project directories and project config only.
  services      Discovery-backed services/config apply path.
  dependencies  Dependency decision preview/interview/apply.
  run-plans    Regenerate run-plan JSON artifacts from current config.
  ci            CI/server local env/config setup.
  shipping      Infer/review mixed-driver continuous-delivery pipelines.

Generates project memory under .ops.project/config by default.
Use --export-yaml --apply to write or refresh .ops.yaml as an optional compatibility export.

Generates and validates project setup values:
  .ops.project/config project memory files
  .ops.yaml compatibility export (optional; ops setup export-yaml --apply)
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
    project|ci|shipping)
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
    discover|apply-services|dependencies|run-plans|export-yaml|import-yaml|show|check|doctor|help|--help|-h)
      EXPLICIT_SETUP_TARGET=true
      SUBCMD="$1"
      shift
      ;;
  esac
fi

while [[ $# -gt 0 ]]; do
  _arg="$1"
  case "${_arg}" in
    --dry-run) DRY_RUN=true ;;
    --apply) APPLY=true ;;
    --interactive) INTERACTIVE=true ;;
    --export-yaml) EXPORT_YAML=true ;;
    --confirm-inferred) CONFIRM_INFERRED=true ;;
    --check) EXPLICIT_SETUP_TARGET=true; SUBCMD="check" ;;
    --json) JSON_OUTPUT=true ;;
    --refresh) REFRESH=true ;;
    --action=*) RUN_PLAN_ACTIONS="${RUN_PLAN_ACTIONS} ${_arg#*=}" ;;
    --actions=*) RUN_PLAN_ACTIONS="${RUN_PLAN_ACTIONS} ${_arg#*=}" ;;
    --action|--actions)
      die "${_arg} requires ${_arg}=name or ${_arg}=a,b form" 2
      ;;
    --all|-all) EXPLICIT_SETUP_TARGET=true; SUBCMD="generate" ;;
    --module=*) EXPLICIT_SETUP_TARGET=true; MODULE="${_arg#*=}" ;;
    --module)
      die "--module requires --module=name form for now" 2
      ;;
    --profile=*) PROFILE="${_arg#*=}" ;;
    --profile)
      shift
      [[ $# -gt 0 && "${1}" != --* ]] || die "--profile requires a profile name" 2
      PROFILE="$1"
      ;;
    --global-profile=*) GLOBAL_CI_PROFILE="${_arg#*=}" ;;
    --global-profile)
      shift
      [[ $# -gt 0 && "${1}" != --* ]] || die "--global-profile requires a profile name" 2
      GLOBAL_CI_PROFILE="$1"
      ;;
    --defer-connection) DEFER_CI_CONNECTION=true ;;
    --help|-h)
      _usage_setup
      exit 0
      ;;
    *) die "Unknown flag: ${_arg}. Use --help." ;;
  esac
  shift
done

if [[ -n "${MODULE}" ]]; then
  case "${MODULE}" in
    all) SUBCMD="generate" ;;
    project|ci|dependencies|run-plans|shipping) SUBCMD="${MODULE}" ;;
    services) SUBCMD="apply-services" ;;
    *) die "Unknown setup module: ${MODULE}" 2 ;;
  esac
fi

[[ -z "${SUBCMD}" ]] && SUBCMD="generate"
[[ "${SUBCMD}" == "help" || "${SUBCMD}" == "--help" || "${SUBCMD}" == "-h" ]] && { _usage_setup; exit 0; }
[[ -z "${PROFILE}" ]] && PROFILE="$(setup_default_profile)"
OPS_SETUP_PROFILE="${PROFILE}"
export OPS_SETUP_PROFILE

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

  local run_project=false run_services=false run_dependencies=false run_ci=false run_shipping=false

  if _setup_wizard_choose "Create/update base .ops.project structure?" "y"; then
    run_project=true
  fi
  if _setup_wizard_choose "Discover and apply runtime services/config?" "y"; then
    run_services=true
  fi
  if _setup_wizard_choose "Review service dependencies?" "y"; then
    run_dependencies=true
  fi
  if _setup_wizard_choose "Configure a deployment connection (saved, new, or project-only)?" "n"; then
    run_ci=true
  fi
  if _setup_wizard_choose "Configure shipping pipelines?" "n"; then
    run_shipping=true
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
  if [[ "${run_shipping}" == "true" ]]; then
    _run_shipping_setup_module
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
      printf 'cache/\n'
      printf 'generated/\n'
      printf 'profiles/\n'
      printf '.history/\n'
    } > "${file}"
    ops_ok "Wrote ${file#${OPS_PROJECT_ROOT}/}"
  else
    local changed=false
    for item in 'secrets/' 'logs/' 'run/' 'cache/' 'generated/' 'profiles/' '.history/'; do
      if ! grep -qx "${item}" "${file}" 2>/dev/null; then
        printf '%s\n' "${item}" >> "${file}"
        changed=true
      fi
    done
    [[ "${changed}" == "true" ]] && ops_ok "Updated ${file#${OPS_PROJECT_ROOT}/}"
  fi
  return 0
}

_write_project_launcher_file() {
  local file="$1"

  if [[ -e "${file}" ]]; then
    ops_info "Project launcher exists: ${file#${OPS_PROJECT_ROOT}/}"
    return 0
  fi

  cat > "${file}" <<'EOF'
#!/usr/bin/env bash
# Project-local ops launcher.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/.ops/core/main.sh" ]]; then
  OPS_PROJECT_ROOT="${SCRIPT_DIR}" OPS_CORE_ROOT="${SCRIPT_DIR}/.ops/core" exec bash "${SCRIPT_DIR}/.ops/core/main.sh" "$@"
fi

if command -v ops >/dev/null 2>&1; then
  OPS_PROJECT_ROOT="${SCRIPT_DIR}" exec ops "$@"
fi

printf '[ERROR] ops package not found. Expected .ops/core/main.sh or a global ops command on PATH.\n' >&2
exit 1
EOF

  chmod +x "${file}" 2>/dev/null || true
  ops_ok "Wrote ${file#${OPS_PROJECT_ROOT}/}"
}

_write_project_launchers() {
  _write_project_launcher_file "${OPS_PROJECT_ROOT}/ops.sh"
}

_project_base_json() {
  require_bins jq
  local project_name
  project_name="$(basename "${OPS_PROJECT_ROOT}")"
  if [[ -f "${OPS_PROJECT_CONFIG_DIR}/project.json" ]]; then
    project_name="$(jq -r '.name // empty' "${OPS_PROJECT_CONFIG_DIR}/project.json" 2>/dev/null || true)"
    [[ -z "${project_name}" ]] && project_name="$(basename "${OPS_PROJECT_ROOT}")"
  elif manifest_exists; then
    project_name="$(yq e '.project.name // ""' "${OPS_MANIFEST}" 2>/dev/null || true)"
    [[ -z "${project_name}" || "${project_name}" == "null" ]] && project_name="$(basename "${OPS_PROJECT_ROOT}")"
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
  _write_project_launchers
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

_configured_service_process_exists() {
  local id="$1" name="$2"
  if project_config_services_exists; then
    manifest_get_service_list_field "${id}" "run.processes.name" 2>/dev/null | grep -qFx "${name}"
    return $?
  fi
  manifest_exists || return 1
  yq e ".services[] | select(.id == \"${id}\") | .run.processes[]?.name" "${OPS_MANIFEST}" 2>/dev/null | grep -qFx "${name}"
}

_process_output_default_enabled() {
  local id="$1" name="$2"

  if project_config_services_exists || manifest_exists; then
    if _configured_service_process_exists "${id}" "${name}"; then
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

  if (project_config_services_exists || manifest_exists) && ! _configured_service_process_exists "${id}" "${name}"; then
    return 0
  fi

  return 1
}

_resolve_process_decisions_json() {
  local discovery_json="$1"
  local decisions_json='[]'
  local process_entries=()
  local prior_decisions
  prior_decisions="$(_load_decisions_document)"

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
    local default_enabled enabled ambiguous reason confirmed prior
    prior="$(jq -c --arg id "${id}" --arg name "${name}" '
      .decisions[]?
      | select(.type == "process" and .service == $id and .name == $name and .confirmed == true)
    ' <<< "${prior_decisions}")"
    if [[ -n "${prior}" && "${prior}" != "null" ]]; then
      enabled="$(jq -r '.enabled // true' <<< "${prior}")"
      ambiguous="$(jq -r '.ambiguous // false' <<< "${prior}")"
      reason="preserved"
      confirmed=true
      decisions_json="$(jq \
        --arg id "${id}" \
        --arg name "${name}" \
        --arg package "${package}" \
        --argjson enabled "${enabled}" \
        --argjson ambiguous "${ambiguous}" \
        --arg reason "${reason}" \
        --argjson confirmed "${confirmed}" \
        '. + [{type: "process", service: $id, name: $name, package: $package, enabled: $enabled, ambiguous: $ambiguous, reason: $reason, confirmed: $confirmed}]' \
        <<< "${decisions_json}")"
      continue
    fi

    default_enabled="$(_process_output_default_enabled "${id}" "${name}")"
    enabled="${default_enabled}"
    ambiguous=false
    reason="default"
    confirmed=false

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
        confirmed=true
      fi
    fi

    decisions_json="$(jq \
      --arg id "${id}" \
      --arg name "${name}" \
      --arg package "${package}" \
      --argjson enabled "${enabled}" \
      --argjson ambiguous "${ambiguous}" \
      --arg reason "${reason}" \
      --argjson confirmed "${confirmed}" \
      '. + [{type: "process", service: $id, name: $name, package: $package, enabled: $enabled, ambiguous: $ambiguous, reason: $reason, confirmed: $confirmed}]' \
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

_load_decisions_document() {
  if [[ -f "${OPS_PROJECT_CONFIG_DIR}/decisions.json" ]]; then
    cat "${OPS_PROJECT_CONFIG_DIR}/decisions.json"
  else
    printf '%s\n' '{"version":"1","decisions":[]}'
  fi
}

_decisions_mark_confirmed_on_apply() {
  local decisions_json="$1"
  if [[ "${INTERACTIVE}" == "true" || "${CONFIRM_INFERRED}" == "true" ]]; then
    jq '.decisions = ((.decisions // []) | map(. + {confirmed: true}))' <<< "${decisions_json}"
  else
    printf '%s' "${decisions_json}"
  fi
}

_sync_yaml_if_requested() {
  [[ "${EXPORT_YAML}" != "true" ]] && return 0
  # shellcheck source=../lib/manifest_sync.sh
  source "${_SELF_DIR}/../lib/manifest_sync.sh"
  manifest_export_yaml "${OPS_MANIFEST}"
}

_vite_proxy_ports() {
  local dir="${1:?_vite_proxy_ports: directory required}"
  local f
  for f in vite.config.ts vite.config.js vite.config.mts vite.config.cjs; do
    [[ -f "${dir}/${f}" ]] || continue
    grep -Eo 'https?://[^:/]+:[0-9]+' "${dir}/${f}" 2>/dev/null |
      grep -Eo '[0-9]+$' |
      sort -un
    return 0
  done
  return 1
}

_script_localhost_port() {
  local text="${1:-}"
  local port=""
  if [[ "${text}" =~ (localhost|127\.0\.0\.1):([0-9]{2,5}) ]]; then
    port="${BASH_REMATCH[2]}"
    printf '%s' "${port}"
    return 0
  fi
  if [[ "${text}" =~ --port[=\ ]+([0-9]{2,5}) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "${text}" =~ -p[=\ ]+([0-9]{2,5}) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

_discovery_infer_port() {
  local entry="$1"
  local stack path abs_path dev_script port="0"
  stack="$(jq -r '.stack // ""' <<< "${entry}")"
  path="$(jq -r '.path // ""' <<< "${entry}")"
  abs_path="${OPS_PROJECT_ROOT}/${path}"

  case "${stack}" in
    django) printf '8000'; return 0 ;;
    elixir-phoenix) printf '4000'; return 0 ;;
    node)
      dev_script="$(jq -r '.package.scripts.dev // .package.scripts.start // ""' <<< "${entry}")"
      port="$(_script_localhost_port "${dev_script}" || true)"
      [[ -n "${port}" ]] && { printf '%s' "${port}"; return 0; }
      if jq -e '.package.framework? | test("vite|vue")' <<< "${entry}" >/dev/null 2>&1; then
        printf '5173'
        return 0
      fi
      if jq -e '.deps["@nestjs/core"]? != null' <<< "${entry}" >/dev/null 2>&1; then
        printf '3000'
        return 0
      fi
      printf '0'
      ;;
    *) printf '0' ;;
  esac
}

_healthcheck_from_port() {
  local port="$1"
  [[ -n "${port}" && "${port}" != "0" ]] || return 1
  printf 'http://localhost:%s/' "${port}"
}

_service_id_for_port() {
  local target_port="$1" setup_json="$2"
  jq -r --arg port "${target_port}" '
    [.services | to_entries[] | select((.value.port // 0 | tostring) == $port)
      | {id: .key, role: (.value.role // "app"), rank: (
          if (.value.role // "") | test("^(api|process_group)$") then 0
          elif (.value.role // "") == "app" then 1
          else 2 end
        )}]
    | sort_by(.rank)[0].id // ""
  ' <<< "${setup_json}"
}

_infer_service_dependencies_json() {
  local service_id="$1" entry="$2" setup_json="$3"
  local stack path abs_path deps_json="[]" proxy_port script_port dep_id dev_script

  stack="$(jq -r '.stack // ""' <<< "${entry}")"
  path="$(jq -r '.path // ""' <<< "${entry}")"
  abs_path="${OPS_PROJECT_ROOT}/${path}"

  if [[ "${stack}" != "node" ]]; then
    printf '%s' "${deps_json}"
    return 0
  fi

  while IFS= read -r proxy_port; do
    [[ -z "${proxy_port}" ]] && continue
    dep_id="$(_service_id_for_port "${proxy_port}" "${setup_json}")"
    if [[ -n "${dep_id}" && "${dep_id}" != "${service_id}" ]]; then
      deps_json="$(jq -c --arg dep "${dep_id}" 'if index($dep) then . else . + [$dep] end' <<< "${deps_json}")"
    fi
  done < <(_vite_proxy_ports "${abs_path}" 2>/dev/null || true)

  dev_script="$(jq -r '.package.scripts.dev // .package.scripts.start // ""' <<< "${entry}")"
  script_port="$(_script_localhost_port "${dev_script}" 2>/dev/null || true)"
  if [[ -n "${script_port}" ]]; then
    dep_id="$(_service_id_for_port "${script_port}" "${setup_json}")"
    if [[ -n "${dep_id}" && "${dep_id}" != "${service_id}" ]]; then
      deps_json="$(jq -c --arg dep "${dep_id}" 'if index($dep) then . else . + [$dep] end' <<< "${deps_json}")"
    fi
  fi

  printf '%s' "${deps_json}"
}

_service_dependency_default_json() {
  local service_id="$1"
  local deps_json=""

  if [[ -f "${OPS_PROJECT_CONFIG_SERVICES_FILE:-}" ]]; then
    deps_json="$(jq -c --arg id "${service_id}" '
      (.services[]? | select(.id == $id) | .depends_on) // []
    ' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || true)"
  fi

  if ! project_config_services_exists && [[ -z "${deps_json}" || "${deps_json}" == "null" ]] && manifest_exists; then
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
  local discovery_json="$1" decisions_json="$2" setup_json="${3:-}"
  local valid_ids dependency_decisions="[]"
  local service_entries=()
  local prior_decisions
  prior_decisions="$(_load_decisions_document)"

  [[ -n "${setup_json}" ]] || setup_json="$(_generate_setup_json_from_discovery "${discovery_json}")"

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
    local default_deps default_text deps_json reason confirmed reply directory_entry inferred_deps prior

    directory_entry="$(jq -c --arg id "${id}" '.directories[] | select(.id == $id)' <<< "${discovery_json}")"

    prior="$(jq -c --arg id "${id}" '
      .decisions[]?
      | select(.type == "dependency" and .service == $id and .confirmed == true)
    ' <<< "${prior_decisions}")"
    if [[ -n "${prior}" && "${prior}" != "null" ]]; then
      deps_json="$(jq -c '.dependencies // []' <<< "${prior}")"
      default_text="$(_json_array_to_space <<< "${deps_json}")"
      reason="preserved"
      confirmed=true
      dependency_decisions="$(jq \
        --arg id "${id}" \
        --arg path "${path}" \
        --arg role "${role}" \
        --arg reason "${reason}" \
        --argjson confirmed "${confirmed}" \
        --argjson dependencies "${deps_json}" \
        '. + [{type: "dependency", service: $id, path: $path, role: $role, dependencies: $dependencies, confirmed: $confirmed, reason: $reason}]' \
        <<< "${dependency_decisions}")"
      continue
    fi

    default_deps="$(_service_dependency_default_json "${id}")"
    default_text="$(_json_array_to_space <<< "${default_deps}")"
    deps_json="${default_deps}"
    reason="default"
    confirmed=false

    if [[ -n "${default_text}" ]]; then
      reason="preserved"
    elif [[ "$(jq 'length' <<< "${default_deps}")" -eq 0 ]]; then
      inferred_deps="$(_infer_service_dependencies_json "${id}" "${directory_entry}" "${setup_json}")"
      if [[ "$(jq 'length' <<< "${inferred_deps}")" -gt 0 ]]; then
        deps_json="${inferred_deps}"
        default_text="$(_json_array_to_space <<< "${deps_json}")"
        reason="inferred"
      fi
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
  local decisions_json setup_json

  setup_json="$(_generate_setup_json_from_discovery "${discovery_json}")"
  decisions_json="$(_resolve_process_decisions_json "${discovery_json}")"
  _resolve_dependency_decisions_json "${discovery_json}" "${decisions_json}" "${setup_json}"
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
      local id name stack path role env_files_yaml
      id="$(jq -r '.id' <<< "${entry}")"
      name="$(_discovery_human_name "${id}")"
      stack="$(jq -r '.stack' <<< "${entry}")"
      path="$(jq -r '.path' <<< "${entry}")"
      role="$(jq -r '.role' <<< "${entry}")"
      env_files_yaml="$(jq -c '.env_files // []' <<< "${entry}")"

      printf '  - id: %s\n' "${id}"
      printf '    name: "%s"\n' "${name}"
      printf '    stack: %s\n' "${stack}"
      printf '    path: %s\n' "${path}"
      printf '    env_files: %s\n' "${env_files_yaml}"
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

      if [[ "${role}" == "process_group" || "${role}" == "docker_group" ]]; then
        printf '    runner:\n'
        printf '      kind: %s\n' "$(runner_kind_for_role "${role}")"
      fi

      if [[ "${role}" == "process_group" ]]; then
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

_proposed_setup_json_from_discovery() {
  local discovery_json="$1"
  local services_json="{}"

  while IFS= read -r entry; do
    [[ -z "${entry}" ]] && continue
    local id stack role cmd port env_files service_entry
    id="$(jq -r '.id' <<< "${entry}")"
    stack="$(jq -r '.stack' <<< "${entry}")"
    role="$(jq -r '.role' <<< "${entry}")"
    cmd="$(_discovery_start_command "${entry}")"
    port="$(_discovery_infer_port "${entry}")"
    env_files="$(jq -c '.env_files // []' <<< "${entry}")"

    service_entry="$(jq -n \
      --arg runtime "" \
      --arg command "${cmd}" \
      --arg role "${role}" \
      --argjson port "${port}" \
      --argjson env_files "${env_files}" \
      '{runtime: $runtime, port: $port, command: $command, env_files: $env_files, role: $role}')"
    if [[ "${stack}" == "django" ]]; then
      service_entry="$(jq '. + {django: {conda_env: ""}}' <<< "${service_entry}")"
    fi

    services_json="$(jq \
      --arg id "${id}" \
      --argjson entry "${service_entry}" \
      '. + {($id): $entry}' \
      <<< "${services_json}")"
  done < <(jq -c '.directories[] | select(.service == true)' <<< "${discovery_json}")

  jq -n \
    --argjson services "${services_json}" \
    '{
      default_profile: "",
      scaffold: {type: "", package_manager: "", template: ""},
      runtimes: {python: {manager: "", env: "", fallbacks: []}},
      services: $services
    }'
}

_generate_setup_json_from_discovery() {
  local discovery_json="$1"
  local proposed_json
  proposed_json="$(_proposed_setup_json_from_discovery "${discovery_json}")"

  local existing_json
  if [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]; then
    existing_json="$(jq -c '.setup // {}' "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" 2>/dev/null || printf '{}')"
  elif manifest_exists; then
    existing_json="$(yq e -o=json '.setup // {}' "${OPS_MANIFEST}" 2>/dev/null || printf '{}')"
  else
    existing_json='{}'
  fi
  if [[ "${existing_json}" != "{}" ]]; then
    jq -n \
      --arg profile "${PROFILE}" \
      --argjson proposed "${proposed_json}" \
      --argjson existing "${existing_json}" \
      '
        def profile_env_files($profile):
          map(select(
            (split("/")[-1]) as $name
            | if $profile == "staging" then
                ($name | test("^\\.env\\.(production|prod)$|^\\.(production|prod)\\.env$") | not)
              elif ($profile == "production" or $profile == "prod") then
                ($name | test("^\\.env\\.staging$|^\\.staging\\.env$") | not)
              else
                ($name | test("^\\.env\\.(staging|production|prod)$|^\\.(staging|production|prod)\\.env$") | not)
              end
          ));
        def append_new($base; $extra):
          reduce $extra[] as $item
            ($base; if index($item) then . else . + [$item] end);
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
                 | .port = (
                     ($proposed.services[$id].port // 0) as $proposed_port
                     | ($existing.services[$id].port // 0) as $existing_port
                     | if ($existing_port | tonumber) > 0 then $existing_port else $proposed_port end
                   )
                 | .env_files = (
                     (($existing.services[$id].env_files // []) | profile_env_files($profile)) as $existing_env
                     | (($proposed.services[$id].env_files // []) | profile_env_files($profile)) as $proposed_env
                     | if ($existing_env | length) > 0 then
                         if ($profile == "staging" or $profile == "production" or $profile == "prod") then
                           append_new($existing_env; $proposed_env)
                         else
                           $existing_env
                         end
                       else
                         $proposed_env
                       end
                   )
               ))
          )
      '
  else
    printf '%s\n' "${proposed_json}"
  fi
}

_generate_project_config_json_from_discovery() {
  local discovery_json="$1"
  local project_name global_env_files

  project_name="$(basename "${OPS_PROJECT_ROOT}")"
  if [[ -f "${OPS_PROJECT_CONFIG_PROJECT_FILE}" ]]; then
    project_name="$(jq -r '.name // ""' "${OPS_PROJECT_CONFIG_PROJECT_FILE}" 2>/dev/null || true)"
    [[ -z "${project_name}" || "${project_name}" == "null" ]] && project_name="$(basename "${OPS_PROJECT_ROOT}")"
  elif manifest_exists; then
    project_name="$(yq e '.project.name // ""' "${OPS_MANIFEST}" 2>/dev/null || true)"
    [[ -z "${project_name}" || "${project_name}" == "null" ]] && project_name="$(basename "${OPS_PROJECT_ROOT}")"
  fi
  global_env_files="$(jq -c '.global_env_files // []' <<< "${discovery_json}")"

  jq -n \
    --arg version "1" \
    --arg generated_at "$(ops_timestamp)" \
    --arg name "${project_name}" \
    --arg root "${OPS_PROJECT_ROOT}" \
    --arg manifest ".ops.yaml" \
    --arg discovery ".ops.project/generated/discovery.json" \
    --argjson global_env_files "${global_env_files}" \
    '{
      version: $version,
      generated_at: $generated_at,
      name: $name,
      root: $root,
      compatibility_manifest: $manifest,
      discovery_cache: $discovery,
      global_env_files: $global_env_files
    }'
}

_default_settings_json() {
  jq -n '{
    run: {default_mode: "foreground"},
    start: {
      mode: "foreground",
      with_deps: true,
      preview: {enabled: true, lines: 20, wait_seconds: 1},
      healthcheck: {wait: true, timeout_seconds: 60, interval_seconds: 1}
    }
  }'
}

_generate_services_config_json_from_discovery() {
  local discovery_json="$1" setup_json="$2" decisions_json="${3:-}"
  local existing_services_json="[]"

  if project_config_services_exists; then
    existing_services_json="$(jq -c '.services // []' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || printf '[]')"
  elif manifest_exists; then
    existing_services_json="$(yq e -o=json '.services // []' "${OPS_MANIFEST}" 2>/dev/null || printf '[]')"
  fi
  [[ -n "${existing_services_json}" && "${existing_services_json}" != "null" ]] || existing_services_json="[]"
  [[ -n "${decisions_json}" ]] || decisions_json='{"decisions":[]}'

  jq \
    --arg generated_at "$(ops_timestamp)" \
    --arg profile "${PROFILE}" \
    --argjson setup "${setup_json}" \
    --argjson existing_services "${existing_services_json}" \
    --argjson decisions "${decisions_json}" \
    '
      def profile_env_files($profile):
        map(select(
          (split("/")[-1]) as $name
          | if $profile == "staging" then
              ($name | test("^\\.env\\.(production|prod)$|^\\.(production|prod)\\.env$") | not)
            elif ($profile == "production" or $profile == "prod") then
              ($name | test("^\\.env\\.staging$|^\\.staging\\.env$") | not)
            else
              ($name | test("^\\.env\\.(staging|production|prod)$|^\\.(staging|production|prod)\\.env$") | not)
            end
        ));
      def append_new($base; $extra):
        reduce $extra[] as $item
          ($base; if index($item) then . else . + [$item] end);
    {
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
            runner: (($existing_services[]? | select(.id == $directory.id) | .runner) // (
              if .role == "process_group" then {kind: "process_group"}
              elif .role == "docker_group" then {kind: "compose"}
              else {kind: "stack"}
              end
            )),
            build: (($existing_services[]? | select(.id == $directory.id) | .build) // (.build // {} | .outputs = ((.outputs // []) | map(select(.enabled != false) | {name, package})))),
            run: (($existing_services[]? | select(.id == $directory.id) | .run) // (if .role == "process_group" then {processes: ((.build.outputs // []) | map(select(.enabled != false) | {name}))} else {} end)),
            actions: (($existing_services[]? | select(.id == $directory.id) | .actions) // {}),
            compose_files: (
              [($existing_services[]? | select(.id == $directory.id) | .compose_files)][0] as $existing
              | if ($existing | type) == "array" and ($existing | length) > 0 then $existing
                else ($directory.compose_files // [])
                end
            ),
            env_files: (
              (([($existing_services[]? | select(.id == $directory.id) | .env_files)][0] // []) | profile_env_files($profile)) as $existing
              | (($directory.env_files // $setup.services[$directory.id].env_files // []) | profile_env_files($profile)) as $proposed
              | if ($existing | type) == "array" and ($existing | length) > 0 then
                  if ($profile == "staging" or $profile == "production" or $profile == "prod") then
                    append_new($existing; $proposed)
                  else
                    $existing
                  end
                else $proposed
                end
            ),
            env_policy: (
              ($existing_services[]? | select(.id == $directory.id) | .env_policy)
              // "dev_file"
            ),
            env_materialization: (($existing_services[]? | select(.id == $directory.id) | .env_materialization) // ""),
            env_output_file: (($existing_services[]? | select(.id == $directory.id) | .env_output_file) // ""),
            depends_on: (($decisions.decisions[]? | select(.type == "dependency" and .service == $directory.id) | .dependencies) // (($existing_services[]? | select(.id == $directory.id) | .depends_on) // [])),
            healthcheck: (
              ($existing_services[]? | select(.id == $directory.id) | .healthcheck)
              // (if ($setup.services[$directory.id].port // 0) > 0 then "http://localhost:\($setup.services[$directory.id].port)/" else "" end)
              // ""
            ),
            setup: {
              command: ($setup.services[.id].command // ""),
              env_files: ($setup.services[.id].env_files // []),
              port: ($setup.services[.id].port // 0),
              runtime: ($setup.services[.id].runtime // "")
            },
            meta: {
              source: "setup_discovery",
              confirmed_by_user: (
                any($decisions.decisions[]?; .type == "dependency" and .service == $directory.id and .confirmed == true)
                or any($decisions.decisions[]?; .type == "process" and .service == $directory.id and .confirmed == true)
              )
            }
          }
      ]
    }' <<< "${discovery_json}"
}

_materialize_project_config_from_discovery() {
  local discovery_json="$1" setup_json="$2" profile_json="$3" decisions_json="${4:-}"
  local settings_json="{}" services_tmp

  mkdir -p "${OPS_PROJECT_CONFIG_DIR}"
  if [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]; then
    settings_json="$(jq -c '.settings // {}' "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" 2>/dev/null || printf '{}')"
  elif manifest_exists; then
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
  local project_name settings_json services_config global_env_files

  project_name="$(basename "${OPS_PROJECT_ROOT}")"
  settings_json="$(_default_settings_json)"
  services_config="$(_generate_services_config_json_from_discovery "${discovery_json}" "${setup_json}" "${decisions_json}")"
  global_env_files="$(jq -c '.global_env_files // []' <<< "${discovery_json}")"

  jq -n \
    --arg project_name "${project_name}" \
    --arg profile "${PROFILE}" \
    --arg generated_at "$(ops_timestamp)" \
    --argjson settings "${settings_json}" \
    --argjson setup "${setup_json}" \
    --argjson profile_config "${profile_json}" \
    --argjson services_config "${services_config}" \
    --argjson global_env_files "${global_env_files}" \
    '{
      version: "1",
      project: {
        name: $project_name,
        global_env_files: $global_env_files,
        defaults: {env_policy: "dev_file"}
      },
      services: ($services_config.services | map(
        {
          id,
          name,
          stack,
          path,
          compose_files: (.compose_files // []),
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
        + (if .runner.kind == "process_group" then {runner: .runner, build: .build, run: .run}
           elif .runner.kind == "compose" then {runner: .runner}
           else {} end)
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
            compose_files: (.compose_files // []),
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
          + (if .runner.kind == "process_group" then {runner: .runner, build: .build, run: .run}
             elif .runner.kind == "compose" then {runner: .runner}
             else {} end)
        )
    ' <<< "${services_config}"
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

  printf '\nEnv Files\n'
  jq -r '
    .global_env_files // []
    | if length > 0 then "  project: " + join(", ") else empty end
  ' <<< "${discovery_json}"
  jq -r '
    .directories[]
    | select((.env_files // []) | length > 0)
    | "  \(.id): " + (.env_files | join(", "))
  ' <<< "${discovery_json}"
  if ! jq -e '((.global_env_files // []) | length > 0) or ([.directories[]? | select((.env_files // []) | length > 0)] | length > 0)' <<< "${discovery_json}" >/dev/null; then
    printf '  none\n'
  fi

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

  printf '\nProposed project config services from discovery:\n'
  printf 'services:\n'
  _discovery_services_yaml "${discovery_json}"

  printf '\nProposed setup config from discovery:\n'
  _generate_setup_json_from_discovery "${discovery_json}" | jq '.'
}

_print_service_merge_summary() {
  local services_json="$1"

  printf '\nCurrent runtime services:\n'
  if project_config_services_exists; then
    jq -r '.services[]?.id // empty' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null |
      while IFS= read -r id; do
        [[ -n "${id}" && "${id}" != "null" ]] && printf '  - %s\n' "${id}"
      done
  elif manifest_exists; then
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
  local removed current_ids='[]'
  if project_config_services_exists; then
    current_ids="$(jq -c '[.services[]?.id // empty]' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || printf '[]')"
  elif manifest_exists; then
    current_ids="$(yq e -o=json '[.services[].id] // []' "${OPS_MANIFEST}" 2>/dev/null || printf '[]')"
  fi
  removed="$(jq -r -n \
    --argjson current "${current_ids}" \
    --argjson proposed "$(jq '[.[].id]' <<< "${services_json}")" \
    '$current - $proposed | .[]?' 2>/dev/null || true)"
  if [[ -n "${removed}" ]]; then
    printf '%s\n' "${removed}" | while IFS= read -r id; do printf '  - %s\n' "${id}"; done
  else
    printf '  none\n'
  fi
}

_run_apply_services() {
  require_bins jq
  require_manifest_or_config

  local discovery_json decisions_json setup_json profile_json services_config services_json services_tmp

  ops_section "ops setup apply-services"
  discovery_json="$(discovery_scan_project_json)"
  decisions_json="$(_resolve_setup_decisions_json "${discovery_json}")"
  discovery_json="$(_apply_discovery_decisions_json "${discovery_json}" "${decisions_json}")"
  setup_json="$(_generate_setup_json_from_discovery "${discovery_json}")"
  profile_json="$(_generate_profile_json "${PROFILE}")"
  services_config="$(_generate_services_config_json_from_discovery "${discovery_json}" "${setup_json}" "${decisions_json}")"
  services_json="$(jq -c '.services' <<< "${services_config}")"

  _print_discovery_preview "${discovery_json}"
  _print_dependency_decisions_preview "${decisions_json}"
  _print_service_merge_summary "${services_json}"

  printf '\nProposed runtime services:\n'
  jq -r '.[].id' <<< "${services_json}" | while IFS= read -r id; do
    [[ -n "${id}" ]] && printf '  + %s\n' "${id}"
  done

  if [[ "${APPLY}" != "true" ]]; then
    printf '\n'
    ops_info "Preview only. Use --apply to write .ops.project/config/services.json."
    return 0
  fi

  decisions_json="$(_decisions_mark_confirmed_on_apply "${decisions_json}")"
  _ensure_project_base
  printf '%s\n' "${discovery_json}" > "${OPS_DISCOVERY_FILE}"
  _materialize_project_config_from_discovery "${discovery_json}" "${setup_json}" "${profile_json}" "${decisions_json}"
  printf '%s\n' "${setup_json}" > "${OPS_PROJECT_GENERATED_DIR}/setup.json"
  printf '%s\n' "${profile_json}" > "$(setup_profile_file "${PROFILE}")"
  _materialize_project_structure_reference
  _materialize_project_values_metadata

  ops_ok "Updated .ops.project/config/services.json from discovery"
  if [[ "${EXPORT_YAML}" == "true" ]]; then
    _sync_yaml_if_requested
  else
    ops_info "Project config updated. Use --export-yaml --apply only if you need the YAML compatibility export."
  fi
}

_run_dependencies() {
  require_bins jq

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
  decisions_json="$(_decisions_mark_confirmed_on_apply "${decisions_json}")"
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
  [[ -n "${GLOBAL_CI_PROFILE}" ]] && args+=(--global-profile "${GLOBAL_CI_PROFILE}")
  [[ "${DEFER_CI_CONNECTION}" == "true" ]] && args+=(--defer-connection)
  bash "${_SELF_DIR}/ci.sh" "${args[@]}"

  if [[ "${APPLY}" == "true" ]]; then
    bash "${_SELF_DIR}/ci.sh" env --apply
  else
    ops_info "CI env template is a separate local file. Preview with: ops ci env"
  fi
}

_run_shipping_setup_module() {
  local args=()
  [[ "${INTERACTIVE}" == "true" ]] && args+=(--interactive)
  [[ "${REFRESH}" == "true" ]] && args+=(--refresh)
  [[ "${APPLY}" == "true" ]] && args+=(--apply)
  [[ "${JSON_OUTPUT}" == "true" ]] && args+=(--json)
  bash "${_SELF_DIR}/setup-shipping.sh" "${args[@]}"
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
  require_bins jq

  local structure_file
  structure_file="${OPS_PROJECT_GENERATED_DIR}/project_structure.json"

  mkdir -p "${OPS_PROJECT_GENERATED_DIR}"

  local services_json groups_json
  services_json='[]'
  groups_json='{}'

  local id name path group
  while IFS= read -r id; do
    [[ -z "${id}" || "${id}" == "null" ]] && continue
    name="$(manifest_get_service_field "${id}" name)"
    path="$(manifest_get_service_field "${id}" path)"
    [[ -z "${path}" || "${path}" == "null" ]] && continue
    [[ -z "${name}" || "${name}" == "null" ]] && name="${id}"

    group="${path%%/*}"
    [[ -n "${group}" && "${group}" != "${path}" ]] || group="."

    services_json="$(jq \
      --arg id "${id}" \
      --arg name "${name}" \
      --arg path "${path}" \
      --arg group "${group}" \
      '. + [{id: $id, name: $name, path: $path, group: $group}]' \
      <<< "${services_json}")"

    groups_json="$(jq \
      --arg group "${group}" \
      --arg id "${id}" \
      --arg name "${name}" \
      --arg path "${path}" \
      '.[$group] = ((.[$group] // []) + [{id: $id, name: $name, path: $path}])' \
      <<< "${groups_json}")"
  done < <(manifest_list_services)

  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --argjson services "${services_json}" \
    --argjson groups "${groups_json}" \
    '{
      "$schema": "./schema.json",
      meta: {
        description: "Generated by ops setup from configured services.",
        generated_at: $generated_at,
        paths_relative_to: "repository root"
      },
      version: "1.0.0",
      services: $services,
      groups: $groups
    }' > "${structure_file}"

    ops_ok "Materialized .ops.project/generated/project_structure.json from configured services"
}

_materialize_project_values_metadata() {
  require_bins jq

  local values_file tmp_values
  values_file="${OPS_PROJECT_GENERATED_DIR}/project_values.json"
  mkdir -p "${OPS_PROJECT_GENERATED_DIR}"

  local project_name
  project_name="$(manifest_get_project_field name 2>/dev/null || true)"
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

_auto_backup_config() {
  [[ -d "${OPS_PROJECT_CONFIG_DIR}" ]] || return 0
  find "${OPS_PROJECT_CONFIG_DIR}" -maxdepth 1 -type f -name '*.json' -print -quit 2>/dev/null | grep -q . || return 0
  local snapshot_id
  snapshot_id="$(bash "${_SELF_DIR}/backup.sh" create --label pre-setup 2>/dev/null | tail -n 1 || true)"
  if [[ -n "${snapshot_id}" ]]; then
    ops_info "Pre-setup backup: ${snapshot_id}"
  else
    ops_warn "Pre-setup backup could not be created; continuing setup."
  fi
}

_apply_generated() {
  local setup_tmp profile_tmp discovery_tmp decisions_tmp discovery_file had_manifest=false
  require_bins jq
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

  local decisions_content
  decisions_content="$(_decisions_mark_confirmed_on_apply "$(cat "${decisions_tmp}")")"
  printf '%s\n' "${decisions_content}" > "${decisions_tmp}.confirmed"
  mv "${decisions_tmp}.confirmed" "${decisions_tmp}"

  [[ "${EXPORT_YAML}" == "true" && -f "${OPS_MANIFEST}" ]] && _backup_file "${OPS_MANIFEST}"
  _auto_backup_config
  _ensure_project_base
  if [[ -s "${discovery_tmp}" ]]; then
    printf '%s\n' "$(cat "${discovery_tmp}")" > "${OPS_DISCOVERY_FILE}"
    discovery_file="${OPS_DISCOVERY_FILE}"
    _materialize_project_config_from_discovery "$(cat "${discovery_tmp}")" "$(cat "${setup_tmp}")" "$(cat "${profile_tmp}")" "$(cat "${decisions_tmp}")"
    ops_ok "Wrote ${discovery_file#${OPS_PROJECT_ROOT}/}"
  fi
  cp "${setup_tmp}" "${OPS_PROJECT_GENERATED_DIR}/setup.json"
  cp "${profile_tmp}" "$(setup_profile_file "${PROFILE}")"
  rm -f "${OPS_PROJECT_GENERATED_DIR}/setup.yaml" "${OPS_PROFILES_DIR}/${PROFILE}.yaml" >/dev/null 2>&1 || true
  _materialize_project_structure_reference
  _materialize_project_values_metadata
  rm -f "${setup_tmp}" "${profile_tmp}" "${discovery_tmp}" "${decisions_tmp}" "${discovery_tmp}.decided"
  ops_ok "Materialized .ops.project/config and generated setup artifacts"
  if [[ "${EXPORT_YAML}" == "true" ]]; then
    _sync_yaml_if_requested
  elif [[ "${had_manifest}" == "true" ]]; then
    ops_info "Project config updated. YAML compatibility export unchanged."
  else
    ops_info "Project config written. YAML compatibility export not created."
  fi
}

_show_setup() {
  ops_section "ops setup show"
  printf 'Project config: .ops.project/config (%s)\n' "$(project_config_services_exists && printf exists || printf missing)"
  printf 'YAML compatibility export: %s (%s)\n' "${OPS_MANIFEST#${OPS_PROJECT_ROOT}/}" "$([[ -f "${OPS_MANIFEST}" ]] && printf exists || printf missing)"
  printf 'Profile: %s\n' "${PROFILE}"
  printf 'Materialized profile: %s (%s)\n' ".ops.project/profiles/${PROFILE}.json" "$( [[ -f "$(setup_profile_file "${PROFILE}")" ]] && printf exists || printf missing)"
  printf '\nSetup\n'
  if [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]; then
    jq '.setup // {}' "${OPS_PROJECT_CONFIG_SETTINGS_FILE}"
  elif setup_exists; then
    yq e -P '.setup' "${OPS_MANIFEST}"
  elif project_config_services_exists; then
    _generate_setup_json
  else
    jq -n '{}'
  fi
  printf '\nProfile config\n'
  if [[ -f "${OPS_PROJECT_CONFIG_PROFILES_FILE}" ]] && \
     [[ "$(jq -r --arg p "${PROFILE}" '.profiles[$p] // ""' "${OPS_PROJECT_CONFIG_PROFILES_FILE}" 2>/dev/null)" != "" ]]; then
    jq --arg p "${PROFILE}" '.profiles[$p]' "${OPS_PROJECT_CONFIG_PROFILES_FILE}"
  elif manifest_exists && [[ "$(yq e ".profiles.${PROFILE} // \"\"" "${OPS_MANIFEST}" 2>/dev/null)" != "" ]]; then
    yq e -P ".profiles.${PROFILE}" "${OPS_MANIFEST}"
  else
    _generate_profile_json "${PROFILE}"
  fi
}

_run_export_yaml() {
  # shellcheck source=../lib/manifest_sync.sh
  source "${_SELF_DIR}/../lib/manifest_sync.sh"

  ops_section "ops setup export-yaml"
  project_config_services_exists || die "Missing .ops.project/config/services.json. Run ops setup --apply first." 2

  if [[ "${APPLY}" != "true" ]]; then
    ops_info "Preview only. Use --apply to write ${OPS_MANIFEST#${OPS_PROJECT_ROOT}/} from .ops.project/config."
    manifest_json_from_project_config | yq e -P '.' | head -n 60
    return 0
  fi

  manifest_export_yaml "${OPS_MANIFEST}"
}

_run_import_yaml() {
  # shellcheck source=../lib/manifest_sync.sh
  source "${_SELF_DIR}/../lib/manifest_sync.sh"

  ops_section "ops setup import-yaml"
  manifest_exists || die "No .ops.yaml to import at ${OPS_MANIFEST}" 2

  if [[ "${APPLY}" != "true" ]]; then
    ops_info "Preview only. Use --apply to materialize .ops.yaml into .ops.project/config/."
    yq e -P '.services[].id' "${OPS_MANIFEST}" 2>/dev/null | sed 's/^/  service: /'
    return 0
  fi

  manifest_import_yaml
}

_doctor_setup() {
  local fail=0
  require_manifest_or_config
  ops_section "ops setup doctor"
  if project_config_services_exists; then
    require_bins jq
  else
    require_bins yq
  fi

  if setup_validate; then
    ops_ok "setup config valid or not yet generated"
  else
    ops_error "setup config invalid"
    fail=$((fail+1))
  fi
  if setup_profile_validate "${PROFILE}"; then
    ops_ok "profiles.${PROFILE} valid or not yet generated"
  else
    ops_error "profiles.${PROFILE} invalid"
    fail=$((fail+1))
  fi

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

_run_setup_check() {
  require_bins jq
  local discovery_json decisions_json proposed_setup_json current_json cached_json report_json exit_code=0

  discovery_json="$(discovery_scan_project_json)"
  decisions_json="$(_resolve_setup_decisions_json "${discovery_json}")"
  discovery_json="$(_apply_discovery_decisions_json "${discovery_json}" "${decisions_json}")"
  proposed_setup_json="$(_proposed_setup_json_from_discovery "${discovery_json}")"
  current_json="$(setup_check_load_current_json)"
  cached_json='{}'
  if [[ -f "${OPS_DISCOVERY_FILE:-}" ]]; then
    cached_json="$(cat "${OPS_DISCOVERY_FILE}")"
  fi
  report_json="$(setup_check_build_report_json "${discovery_json}" "${proposed_setup_json}" "${current_json}" "${cached_json}")"

  if [[ "${JSON_OUTPUT}" == "true" ]]; then
    jq '.' <<< "${report_json}"
    setup_check_has_drift "${report_json}" && exit_code=1
    exit "${exit_code}"
  fi

  setup_check_print_report "${report_json}" || exit_code=1
  exit "${exit_code}"
}

_run_plan_actions() {
  local actions="${RUN_PLAN_ACTIONS//,/ }"
  if [[ -z "${actions// /}" ]]; then
    actions="start status build test lint logs stop"
  fi
  printf '%s\n' ${actions} | awk 'NF && !seen[$0]++'
}

_run_run_plans() {
  require_bins jq
  require_manifest_or_config

  local report_json="[]"
  local service_id action file status

  ops_section "ops setup run-plans"

  while IFS= read -r service_id; do
    [[ -z "${service_id}" || "${service_id}" == "null" ]] && continue
    while IFS= read -r action; do
      [[ -z "${action}" || "${action}" == "null" ]] && continue
      if [[ "${APPLY}" == "true" ]]; then
        file="$(run_plan_write "${action}" "${service_id}")"
        status="written"
      else
        file="$(run_plan_file "${service_id}" "${action}")"
        status="planned"
      fi
      report_json="$(jq -c \
        --arg service "${service_id}" \
        --arg action "${action}" \
        --arg status "${status}" \
        --arg file "${file#${OPS_PROJECT_ROOT}/}" \
        '. + [{service: $service, action: $action, status: $status, file: $file}]' \
        <<< "${report_json}")"
    done < <(_run_plan_actions)
  done < <(manifest_list_services)

  if [[ "${JSON_OUTPUT}" == "true" ]]; then
    jq '{run_plans: .}' <<< "${report_json}"
    return 0
  fi

  if [[ "${APPLY}" == "true" ]]; then
    ops_ok "Regenerated run plans"
  else
    ops_info "Preview only. Use --apply to write run plans."
  fi

  jq -r '.[] | "  \(.status): \(.service).\(.action) -> \(.file)"' <<< "${report_json}"
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
  shipping)
    _run_shipping_setup_module
    ;;
  run-plans)
    _run_run_plans
    ;;
  export-yaml)
    _run_export_yaml
    ;;
  import-yaml)
    _run_import_yaml
    ;;
  show)
    _show_setup
    ;;
  doctor)
    _doctor_setup
    ;;
  check)
    _run_setup_check
    ;;
  generate)
    ops_section "ops setup"
    if ! manifest_exists; then
      ops_warn "No YAML compatibility export found. Running discovery-driven project config setup."
      discovery_json="$(discovery_scan_project_json)"
      decisions_json="$(_resolve_setup_decisions_json "${discovery_json}")"
      discovery_json="$(_apply_discovery_decisions_json "${discovery_json}" "${decisions_json}")"
      _print_discovery_preview "${discovery_json}"
      _print_dependency_decisions_preview "${decisions_json}"
      _print_discovery_config_proposal "${discovery_json}"
      if [[ "${APPLY}" == "true" ]]; then
        _apply_generated
      else
        ops_info "Preview only. Use --apply to create .ops.project/config."
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
