#!/usr/bin/env bash
# .ops/core/commands/show.sh — Read-only action execution plan inspector.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/settings.sh"
source "${_SELF_DIR}/../lib/setup.sh"
source "${_SELF_DIR}/../lib/env.sh"
source "${_SELF_DIR}/../lib/cross_shell.sh"
source "${_SELF_DIR}/../lib/run_plan.sh"
source "${_SELF_DIR}/../lib/runner.sh"

_usage_show() {
  cat <<'EOF'
Usage: ops show <action> <service_id> [--ci-mode] [--unmask-env]

Shows how ops would resolve and run an action without executing it.

Examples:
  ./ops.sh show start backend
  ./ops.sh show test web --ci-mode
EOF
}

ACTION=""
SVC_ID=""
CI_FLAG=""
UNMASK_ENV=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    help|--help|-h)
      _usage_show
      exit 0
      ;;
    --ci-mode)
      CI_FLAG="--ci-mode"
      shift
      ;;
    --unmask-env)
      UNMASK_ENV=true
      shift
      ;;
    --*)
      die "Unknown flag: $1"
      ;;
    *)
      if [[ -z "${ACTION}" ]]; then
        ACTION="$1"
      elif [[ -z "${SVC_ID}" ]]; then
        SVC_ID="$1"
      else
        die "Usage: ops show <action> <service_id> [--ci-mode] [--unmask-env]"
      fi
      shift
      ;;
  esac
done

if [[ -z "${ACTION}" || -z "${SVC_ID}" ]]; then
  _usage_show >&2
  exit 2
fi

require_manifest_or_config

if ! manifest_list_services | grep -qFx "${SVC_ID}"; then
  die "Unknown service: '${SVC_ID}'" 2
fi

RUN_PLAN_JSON="$(run_plan_generate_json "${ACTION}" "${SVC_ID}")"
RUN_PLAN_FILE="$(run_plan_write_json "${SVC_ID}" "${ACTION}" "${RUN_PLAN_JSON}")"

SVC_NAME="$(manifest_get_service_field "${SVC_ID}" name)"
SVC_PATH="$(manifest_get_service_field "${SVC_ID}" path)"
STACK="$(manifest_get_service_field "${SVC_ID}" stack)"
RUNNER_KIND="$(manifest_get_service_field "${SVC_ID}" "runner.kind")"
EXPLICIT_CMD="$(manifest_get_service_field "${SVC_ID}" "actions.${ACTION}")"
ABS_PATH="${OPS_PROJECT_ROOT}/${SVC_PATH}"
SVC_OVERRIDE="${OPS_PROJECT_ROOT}/.ops/commands/${SVC_ID}/${ACTION}.sh"
GLOBAL_OVERRIDE="${OPS_PROJECT_ROOT}/.ops/commands/${ACTION}.sh"
STACK_FILE="${OPS_CORE_ROOT}/stacks/${STACK}.sh"
STACK_DISPATCH_FUNC="${STACK//-/_}_dispatch"
SETUP_PROFILE="$(setup_default_profile)"
SETUP_CMD=""
if [[ "${ACTION}" == "start" ]]; then
  SETUP_CMD="$(setup_service_start_command "${SVC_ID}")"
fi
SETUP_PORT="$(setup_service_get "${SVC_ID}" port "0")"
SETUP_RUNTIME="$(setup_service_get "${SVC_ID}" runtime "")"
RUN_MODE="$(ops_setting_mode '.run.default_mode' 'foreground')"
START_MODE="$(ops_setting_mode '.start.mode' 'background')"
START_WITH_DEPS="$(ops_setting_bool '.start.with_deps' 'true')"
START_PREVIEW_ENABLED="$(ops_setting_bool '.start.preview.enabled' 'true')"
START_PREVIEW_LINES="$(ops_setting_int '.start.preview.lines' '20')"
START_PREVIEW_WAIT="$(ops_setting_int '.start.preview.wait_seconds' '1')"

_bool_file() {
  [[ -f "$1" ]] && printf 'yes' || printf 'no'
}

_bool_exec() {
  [[ -x "$1" ]] && printf 'yes' || printf 'no'
}

_stack_default_command() {
  local stack="$1" action="$2"
  run_plan_stack_default_command "${stack}" "${action}"
}

_legacy_target_script() {
  run_plan_legacy_target_script "${ACTION}"
}

_print_python_env_plan() {
  [[ "${STACK}" == "django" ]] || return 0

  printf '\nPython Environment\n'
  local activation
  local django_conda_env
  activation="$(setup_runtime_python_activation)"
  django_conda_env="$(setup_service_django_conda_env "${SVC_ID}")"
  if [[ -n "${django_conda_env}" ]]; then
    printf '  django conda env: %s\n' "${django_conda_env}"
  fi
  printf '  activation: %s\n' "${activation}"
  if [[ "${activation}" == conda\ activate* ]]; then
    if command -v conda >/dev/null 2>&1; then
      printf '  conda binary: %s\n' "$(command -v conda)"
    else
      printf '  conda binary: not found in current shell\n'
    fi
  fi

  if [[ -f "${SVC_OVERRIDE}" && -x "${SVC_OVERRIDE}" ]]; then
    printf '  note: local override exists, but start now prefers the setup command from .ops.project.\n'
  fi
}

_print_preflight() {
  printf '\nPreflight Binaries\n'
  local reqs=()
  case "${STACK}" in
    django) reqs=("python|python3") ;;
    node) reqs=("node" "npm") ;;
    go) reqs=("go") ;;
    elixir-phoenix) reqs=("elixir" "mix") ;;
    docker) reqs=("docker") ;;
    custom) reqs=() ;;
  esac

  if [[ ${#reqs[@]} -eq 0 ]]; then
    printf '  none\n'
    return 0
  fi

  local req alt found
  for req in "${reqs[@]}"; do
    found=""
    IFS='|' read -ra alts <<< "${req}"
    for alt in "${alts[@]}"; do
      if command -v "${alt}" >/dev/null 2>&1; then
        found="${alt}: $(command -v "${alt}")"
        break
      fi
    done
    if [[ -n "${found}" ]]; then
      printf '  %s -> %s\n' "${req}" "${found}"
    else
      printf '  %s -> missing\n' "${req}"
    fi
  done
}

_print_env_files() {
  printf '\nEnv Files\n'
  local any=false item
  while IFS= read -r item; do
    [[ -z "${item}" || "${item}" == "null" ]] && continue
    any=true
    printf '  project: %s (%s)\n' "${item}" "$(_bool_file "${OPS_PROJECT_ROOT}/${item}")"
  done < <(manifest_get_field '.project.global_env_files[]?' 2>/dev/null || true)

  while IFS= read -r item; do
    [[ -z "${item}" || "${item}" == "null" ]] && continue
    any=true
    printf '  service: %s (%s)\n' "${item}" "$(_bool_file "${OPS_PROJECT_ROOT}/${item}")"
  done < <(manifest_get_service_list_field "${SVC_ID}" env_files 2>/dev/null || true)

  [[ "${any}" == "true" ]] || printf '  none\n'
}

_print_go_process_group_plan() {
  [[ "${STACK}" == "go" && "${RUNNER_KIND}" == "process_group" ]] || return 0

  printf '\nGo Process Group\n'
  printf '  output dir: %s\n' "$(manifest_get_service_field "${SVC_ID}" 'build.output_dir')"
  printf '  target: %s/%s\n' \
    "$(manifest_get_service_field "${SVC_ID}" 'build.target_os')" \
    "$(manifest_get_service_field "${SVC_ID}" 'build.target_arch')"
  if command -v go >/dev/null 2>&1; then
    printf '  go binary: %s\n' "$(command -v go)"
    printf '  go host: %s\n' "$(tool_host_os go)"
  else
    printf '  go binary: missing\n'
  fi
  printf '  logs: .ops.project/logs/%s/<process>.log\n' "${SVC_ID}"
  printf '  pids: .ops.project/run/%s/<process>.pid\n' "${SVC_ID}"
  printf '  processes:\n'
  manifest_get_service_list_field "${SVC_ID}" "run.processes.name" 2>/dev/null |
    while IFS= read -r proc; do
      [[ -n "${proc}" && "${proc}" != "null" ]] && printf '    - %s\n' "${proc}"
    done
}

ops_section "ops show ${ACTION} ${SVC_ID}"

printf 'Service\n'
printf '  id: %s\n' "${SVC_ID}"
printf '  name: %s\n' "${SVC_NAME:-}"
printf '  stack: %s\n' "${STACK}"
if [[ -n "${RUNNER_KIND}" && "${RUNNER_KIND}" != "null" ]]; then
  printf '  runner kind: %s\n' "${RUNNER_KIND}"
fi
printf '  path: %s\n' "${SVC_PATH}"
printf '  working directory: %s\n' "${ABS_PATH}"
printf '  action: %s\n' "${ACTION}"
if project_config_services_exists; then
  printf '  config source: %s\n' "${OPS_PROJECT_CONFIG_SERVICES_FILE#${OPS_PROJECT_ROOT}/}"
  printf '  compatibility manifest: %s\n' "${OPS_MANIFEST}"
else
  printf '  config source: %s\n' "${OPS_MANIFEST}"
fi
printf '  state dir: %s\n' "${OPS_PROJECT_STATE_DIR}"
printf '  setup profile: %s\n' "${SETUP_PROFILE}"
printf '  run plan: %s\n' "${RUN_PLAN_FILE#${OPS_PROJECT_ROOT}/}"

printf '\nResolution\n'
if runner_is_managed_kind "${RUNNER_KIND}"; then
  printf '  managed runner: %s (service/global overrides and setup command are skipped)\n' "${RUNNER_KIND}"
fi
printf '  1. service override: .ops/commands/%s/%s.sh (exists: %s, executable: %s)\n' \
  "${SVC_ID}" "${ACTION}" "$(_bool_file "${SVC_OVERRIDE}")" "$(_bool_exec "${SVC_OVERRIDE}")"
printf '  2. global override: .ops/commands/%s.sh (exists: %s, executable: %s)\n' \
  "${ACTION}" "$(_bool_file "${GLOBAL_OVERRIDE}")" "$(_bool_exec "${GLOBAL_OVERRIDE}")"
printf '  3. setup command: %s\n' "${SETUP_CMD:-<empty>}"
printf '  4. stack dispatcher: %s (exists: %s, function: %s)\n' \
  "${STACK_FILE#${OPS_PROJECT_ROOT}/}" "$(_bool_file "${STACK_FILE}")" "${STACK_DISPATCH_FUNC}"
printf '  5. manifest action: %s\n' "${EXPLICIT_CMD:-<empty>}"

SELECTED_KIND=""
SELECTED_CMD=""
if runner_is_managed_kind "${RUNNER_KIND}"; then
  SELECTED_KIND="managed stack runner"
  SELECTED_CMD="${STACK_DISPATCH_FUNC} ${ACTION}"
elif [[ -f "${SVC_OVERRIDE}" && -x "${SVC_OVERRIDE}" ]]; then
  SELECTED_KIND="service override"
  SELECTED_CMD="${SVC_OVERRIDE}"
elif [[ -f "${GLOBAL_OVERRIDE}" && -x "${GLOBAL_OVERRIDE}" ]]; then
  SELECTED_KIND="global override"
  SELECTED_CMD="${GLOBAL_OVERRIDE}"
elif [[ "${ACTION}" == "start" && -n "${SETUP_CMD}" && "${SETUP_CMD}" != "null" ]]; then
  SELECTED_KIND="setup command"
  SELECTED_CMD="${SETUP_CMD}"
elif [[ -n "${EXPLICIT_CMD}" && "${EXPLICIT_CMD}" != "null" ]]; then
  SELECTED_KIND="manifest action via stack dispatcher"
  SELECTED_CMD="${EXPLICIT_CMD}"
elif STACK_DEFAULT="$(_stack_default_command "${STACK}" "${ACTION}")"; then
  SELECTED_KIND="stack default"
  SELECTED_CMD="${STACK_DEFAULT}"
elif LEGACY_TARGET="$(_legacy_target_script)" && [[ -n "${LEGACY_TARGET}" ]]; then
  SELECTED_KIND="legacy bridge"
  SELECTED_CMD="scripts/${LEGACY_TARGET}"
else
  SELECTED_KIND="unresolved"
  SELECTED_CMD="<no runner found>"
fi

printf '\nSelected Runner\n'
printf '  kind: %s\n' "${SELECTED_KIND}"
printf '  command: %s\n' "${SELECTED_CMD}"
printf '  cwd: %s\n' "${ABS_PATH}"
if [[ "${SETUP_PORT}" != "0" && -n "${SETUP_PORT}" ]]; then
  printf '  port: %s\n' "${SETUP_PORT}"
fi
if [[ -n "${SETUP_RUNTIME}" && "${SETUP_RUNTIME}" != "null" ]]; then
  printf '  runtime: %s\n' "${SETUP_RUNTIME}"
fi
if [[ "${ACTION}" == "start" ]]; then
  printf '  top-level start mode: %s, log: .ops.project/logs/%s.log, pid: .ops.project/run/%s.pid\n' "${START_MODE}" "${SVC_ID}" "${SVC_ID}"
else
  printf '  run default mode: %s\n' "${RUN_MODE}"
fi

printf '\nSettings\n'
printf '  run.default_mode: %s\n' "${RUN_MODE}"
printf '  start.mode: %s\n' "${START_MODE}"
printf '  start.with_deps: %s\n' "${START_WITH_DEPS}"
printf '  start.preview.enabled: %s\n' "${START_PREVIEW_ENABLED}"
printf '  start.preview.lines: %s\n' "${START_PREVIEW_LINES}"
printf '  start.preview.wait_seconds: %s\n' "${START_PREVIEW_WAIT}"

printf '\nSetup\n'
printf '  setup.default_profile: %s\n' "${SETUP_PROFILE}"
printf '  service.command: %s\n' "${SETUP_CMD:-<empty>}"
printf '  service.port: %s\n' "${SETUP_PORT}"
printf '  service.runtime: %s\n' "${SETUP_RUNTIME:-<empty>}"
printf '  python activation: %s\n' "$(setup_runtime_python_activation)"

if STACK_DEFAULT="$(_stack_default_command "${STACK}" "${ACTION}")"; then
  printf '\nStack Default\n'
  printf '  %s\n' "${STACK_DEFAULT}"
fi

_print_go_process_group_plan
_print_python_env_plan
_print_preflight
_print_env_files

printf '\nResolved Env Context\n'
if [[ "${UNMASK_ENV}" == "true" ]]; then
  # shellcheck disable=SC2086
  env_show_context "${SVC_ID}" --unmask ${CI_FLAG}
else
  # shellcheck disable=SC2086
  env_show_context "${SVC_ID}" ${CI_FLAG}
fi
