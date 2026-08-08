#!/usr/bin/env bash
# .ops/core/lib/run_plan.sh - Shared action resolution and run-plan writer.

set -euo pipefail
if [[ "${_OPS_CORE_RUN_PLAN_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_RUN_PLAN_LOADED=1

# shellcheck source=runner.sh
source "${OPS_CORE_ROOT}/lib/runner.sh"

OPS_RUN_PLANS_DIR="${OPS_RUN_PLANS_DIR:-${OPS_PROJECT_GENERATED_DIR:-${OPS_PROJECT_ROOT}/.ops.project/generated}/run-plans}"
export OPS_RUN_PLANS_DIR

run_plan_file() {
  local service_id="${1:?run_plan_file: service id required}"
  local action="${2:?run_plan_file: action required}"
  printf '%s/%s.%s.json' "${OPS_RUN_PLANS_DIR}" "${service_id}" "${action}"
}

run_plan_stack_default_command() {
  local stack="${1:-}" action="${2:-start}"
  case "${stack}:${action}" in
    django:start) printf 'python -u manage.py runserver 0.0.0.0:8000' ;;
    django:test) printf 'python manage.py test' ;;
    django:stop|node:stop|go:stop|elixir-phoenix:stop|custom:stop) printf 'stop pid from .ops.project/run/${OPS_SERVICE_ID}.pid' ;;
    django:status|node:status|go:status|elixir-phoenix:status|custom:status) printf 'check pid from .ops.project/run/${OPS_SERVICE_ID}.pid' ;;
    node:start) printf 'npm start' ;;
    node:build) printf 'npm run build' ;;
    node:test) printf 'npm test' ;;
    node:lint) printf 'npm run lint' ;;
    go:start) printf 'go run main.go' ;;
    go:build) printf 'go build -o app' ;;
    go:test) printf 'go test ./...' ;;
    elixir-phoenix:start) printf 'mix phx.server' ;;
    elixir-phoenix:test) printf 'mix test' ;;
    elixir-phoenix:build) printf 'mix release' ;;
    docker:start) printf 'docker compose up -d' ;;
    docker:stop) printf 'docker compose down' ;;
    docker:logs) printf 'docker compose logs -f' ;;
    docker:status) printf 'docker compose ps --services --filter status=running' ;;
    *) return 1 ;;
  esac
}

run_plan_legacy_target_script() {
  local action="${1:?run_plan_legacy_target_script: action required}"
  local registry="${OPS_PROJECT_ROOT}/scripts/commands.sh"
  [[ -f "${registry}" ]] || return 1
  bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "${COMMAND_SCRIPTS[$2]:-}"' _ "${registry}" "${action}"
}

_run_plan_bool_file() {
  [[ -f "$1" ]] && printf 'true' || printf 'false'
}

_run_plan_bool_exec() {
  [[ -x "$1" ]] && printf 'true' || printf 'false'
}

_run_plan_service_processes_json() {
  local service_id="${1:?_run_plan_service_processes_json: service id required}"
  local processes_json="[]"
  local proc

  while IFS= read -r proc; do
    [[ -z "${proc}" || "${proc}" == "null" ]] && continue
    processes_json="$(jq -c --arg name "${proc}" '. + [{name: $name}]' <<<"${processes_json}")"
  done < <(project_get_service_list_field "${service_id}" "run.processes.name" 2>/dev/null || true)

  printf '%s' "${processes_json}"
}

_run_plan_build_outputs_json() {
  local service_id="${1:?_run_plan_build_outputs_json: service id required}"
  local outputs_json="[]"
  outputs_json="$(project_get_service_json_field "${service_id}" build.outputs '[]')"

  [[ -n "${outputs_json}" && "${outputs_json}" != "null" ]] && printf '%s' "${outputs_json}" || printf '[]'
}

run_plan_generate_json() {
  local action="${1:?run_plan_generate_json: action required}"
  local service_id="${2:?run_plan_generate_json: service id required}"
  local mode="${3:-}"

  require_bins jq

  if ! project_list_services | grep -qFx "${service_id}"; then
    die "Unknown service: '${service_id}'" 2
  fi

  local svc_name svc_path stack runner_kind explicit_cmd abs_path
  local svc_override global_override stack_file stack_dispatch_func
  local setup_profile setup_cmd setup_port setup_runtime
  local run_mode start_mode start_with_deps start_preview_enabled
  local start_preview_lines start_preview_wait python_activation
  local config_source compatibility_export stack_default legacy_target
  local selected_kind selected_cmd selected_strategy selected_cwd
  local build_output_dir build_target_os build_target_arch
  local service_override_exists service_override_executable
  local global_override_exists global_override_executable stack_file_exists
  local processes_json build_outputs_json

  svc_name="$(project_get_service_field "${service_id}" name)"
  svc_path="$(project_get_service_field "${service_id}" path)"
  stack="$(project_get_service_field "${service_id}" stack)"
  runner_kind="$(project_get_service_field "${service_id}" "runner.kind")"
  explicit_cmd="$(project_get_service_field "${service_id}" "actions.${action}")"
  abs_path="${OPS_PROJECT_ROOT}/${svc_path}"
  svc_override="${OPS_PROJECT_ROOT}/.ops/commands/${service_id}/${action}.sh"
  global_override="${OPS_PROJECT_ROOT}/.ops/commands/${action}.sh"
  stack_file="${OPS_CORE_ROOT}/stacks/${stack}.sh"
  stack_dispatch_func="${stack//-/_}_dispatch"

  setup_profile="$(setup_default_profile)"
  setup_cmd=""
  if [[ "${action}" == "start" ]]; then
    setup_cmd="$(setup_service_start_command "${service_id}")"
  fi
  setup_port="$(setup_service_get "${service_id}" port "0")"
  setup_runtime="$(setup_service_get "${service_id}" runtime "")"
  python_activation="$(setup_runtime_python_activation)"

  run_mode="${mode:-$(ops_setting_mode '.run.default_mode' 'foreground')}"
  start_mode="$(ops_setting_mode '.start.mode' 'background')"
  start_with_deps="$(ops_setting_bool '.start.with_deps' 'true')"
  start_preview_enabled="$(ops_setting_bool '.start.preview.enabled' 'true')"
  start_preview_lines="$(ops_setting_int '.start.preview.lines' '20')"
  start_preview_wait="$(ops_setting_int '.start.preview.wait_seconds' '1')"

  if project_config_services_exists; then
    config_source="${OPS_PROJECT_CONFIG_SERVICES_FILE#${OPS_PROJECT_ROOT}/}"
    compatibility_export="${OPS_MANIFEST#${OPS_PROJECT_ROOT}/}"
  else
    config_source="${OPS_MANIFEST#${OPS_PROJECT_ROOT}/}"
    compatibility_export=""
  fi

  stack_default=""
  if stack_default="$(run_plan_stack_default_command "${stack}" "${action}")"; then
    :
  else
    stack_default=""
  fi

  legacy_target=""
  if legacy_target="$(run_plan_legacy_target_script "${action}")"; then
    :
  else
    legacy_target=""
  fi

  service_override_exists="$(_run_plan_bool_file "${svc_override}")"
  service_override_executable="$(_run_plan_bool_exec "${svc_override}")"
  global_override_exists="$(_run_plan_bool_file "${global_override}")"
  global_override_executable="$(_run_plan_bool_exec "${global_override}")"
  stack_file_exists="$(_run_plan_bool_file "${stack_file}")"

  selected_kind=""
  selected_cmd=""
  selected_strategy=""
  selected_cwd="${abs_path}"
  if runner_is_managed_kind "${runner_kind}"; then
    selected_kind="managed stack runner"
    selected_cmd="${stack_dispatch_func} ${action}"
    selected_strategy="stack"
  elif [[ -f "${svc_override}" && -x "${svc_override}" ]]; then
    selected_kind="service override"
    selected_cmd="${svc_override}"
    selected_strategy="service_override"
  elif [[ -f "${global_override}" && -x "${global_override}" ]]; then
    selected_kind="global override"
    selected_cmd="${global_override}"
    selected_strategy="global_override"
  elif [[ "${action}" == "start" && -n "${setup_cmd}" && "${setup_cmd}" != "null" ]]; then
    selected_kind="setup command"
    selected_cmd="${setup_cmd}"
    selected_strategy="setup_command"
  elif [[ -n "${explicit_cmd}" && "${explicit_cmd}" != "null" ]]; then
    selected_kind="configured action via stack dispatcher"
    selected_cmd="${explicit_cmd}"
    selected_strategy="configured_action"
  elif [[ -n "${stack_default}" ]]; then
    selected_kind="stack default"
    selected_cmd="${stack_default}"
    selected_strategy="stack_default"
  elif [[ -n "${legacy_target}" ]]; then
    selected_kind="legacy bridge"
    selected_cmd="scripts/${legacy_target}"
    selected_strategy="legacy_bridge"
  else
    selected_kind="unresolved"
    selected_cmd="<no runner found>"
    selected_strategy="unresolved"
  fi

  build_output_dir="$(project_get_service_field "${service_id}" 'build.output_dir')"
  build_target_os="$(project_get_service_field "${service_id}" 'build.target_os')"
  build_target_arch="$(project_get_service_field "${service_id}" 'build.target_arch')"
  processes_json="$(_run_plan_service_processes_json "${service_id}")"
  build_outputs_json="$(_run_plan_build_outputs_json "${service_id}")"

  jq -n \
    --argjson version 1 \
    --arg generated_at "$(ops_timestamp)" \
    --arg project_root "${OPS_PROJECT_ROOT}" \
    --arg state_dir "${OPS_PROJECT_STATE_DIR}" \
    --arg config_source "${config_source}" \
    --arg compatibility_export "${compatibility_export}" \
    --arg action "${action}" \
    --arg requested_mode "${mode}" \
    --arg run_mode "${run_mode}" \
    --arg service_id "${service_id}" \
    --arg service_name "${svc_name}" \
    --arg service_path "${svc_path}" \
    --arg service_abs_path "${abs_path}" \
    --arg stack "${stack}" \
    --arg runner_kind "${runner_kind}" \
    --arg explicit_cmd "${explicit_cmd}" \
    --arg setup_profile "${setup_profile}" \
    --arg setup_cmd "${setup_cmd}" \
    --arg setup_port "${setup_port}" \
    --arg setup_runtime "${setup_runtime}" \
    --arg python_activation "${python_activation}" \
    --arg start_mode "${start_mode}" \
    --argjson start_with_deps "${start_with_deps}" \
    --argjson start_preview_enabled "${start_preview_enabled}" \
    --arg start_preview_lines "${start_preview_lines}" \
    --arg start_preview_wait "${start_preview_wait}" \
    --arg service_override "${svc_override}" \
    --arg global_override "${global_override}" \
    --arg stack_file "${stack_file}" \
    --arg stack_dispatch_func "${stack_dispatch_func}" \
    --argjson service_override_exists "${service_override_exists}" \
    --argjson service_override_executable "${service_override_executable}" \
    --argjson global_override_exists "${global_override_exists}" \
    --argjson global_override_executable "${global_override_executable}" \
    --argjson stack_file_exists "${stack_file_exists}" \
    --arg stack_default "${stack_default}" \
    --arg legacy_target "${legacy_target}" \
    --arg selected_kind "${selected_kind}" \
    --arg selected_cmd "${selected_cmd}" \
    --arg selected_strategy "${selected_strategy}" \
    --arg selected_cwd "${selected_cwd}" \
    --arg log_file "${OPS_PROJECT_LOG_DIR}/${service_id}.log" \
    --arg pid_file "${OPS_PROJECT_RUN_DIR}/${service_id}.pid" \
    --arg process_log_dir "${OPS_PROJECT_LOG_DIR}/${service_id}" \
    --arg process_pid_dir "${OPS_PROJECT_RUN_DIR}/${service_id}" \
    --arg build_output_dir "${build_output_dir}" \
    --arg build_target_os "${build_target_os}" \
    --arg build_target_arch "${build_target_arch}" \
    --argjson processes "${processes_json}" \
    --argjson build_outputs "${build_outputs_json}" \
    '{
      version: $version,
      generated_at: $generated_at,
      project: {
        root: $project_root,
        state_dir: $state_dir,
        config_source: $config_source,
        compatibility_export: $compatibility_export
      },
      action: {
        name: $action,
        requested_mode: $requested_mode,
        run_mode: $run_mode
      },
      service: {
        id: $service_id,
        name: $service_name,
        path: $service_path,
        abs_path: $service_abs_path,
        stack: $stack,
        runner_kind: $runner_kind,
        explicit_command: $explicit_cmd
      },
      setup: {
        profile: $setup_profile,
        command: $setup_cmd,
        port: ($setup_port | tonumber? // 0),
        runtime: $setup_runtime,
        python_activation: $python_activation
      },
      settings: {
        run_default_mode: $run_mode,
        start_mode: $start_mode,
        start_with_deps: $start_with_deps,
        start_preview: {
          enabled: $start_preview_enabled,
          lines: ($start_preview_lines | tonumber? // 0),
          wait_seconds: ($start_preview_wait | tonumber? // 0)
        }
      },
      resolution: {
        candidates: {
          service_override: {
            path: $service_override,
            exists: $service_override_exists,
            executable: $service_override_executable
          },
          global_override: {
            path: $global_override,
            exists: $global_override_exists,
            executable: $global_override_executable
          },
          setup_command: $setup_cmd,
          stack_dispatcher: {
            path: $stack_file,
            exists: $stack_file_exists,
            function: $stack_dispatch_func,
            default_command: $stack_default
          },
          configured_action: $explicit_cmd,
          legacy_bridge: $legacy_target
        },
        selected: {
          kind: $selected_kind,
          strategy: $selected_strategy,
          command: $selected_cmd,
          cwd: $selected_cwd
        }
      },
      paths: {
        log_file: $log_file,
        pid_file: $pid_file,
        process_log_dir: $process_log_dir,
        process_pid_dir: $process_pid_dir
      },
      build: {
        output_dir: $build_output_dir,
        target_os: $build_target_os,
        target_arch: $build_target_arch,
        outputs: $build_outputs
      },
      process_group: {
        processes: $processes
      }
    }'
}

run_plan_write_json() {
  local service_id="${1:?run_plan_write_json: service id required}"
  local action="${2:?run_plan_write_json: action required}"
  local json="${3:?run_plan_write_json: json required}"
  local file

  file="$(run_plan_file "${service_id}" "${action}")"
  ensure_dir "$(dirname "${file}")"
  printf '%s\n' "${json}" > "${file}"
  printf '%s' "${file}"
}

run_plan_write() {
  local action="${1:?run_plan_write: action required}"
  local service_id="${2:?run_plan_write: service id required}"
  local mode="${3:-}"
  local json

  json="$(run_plan_generate_json "${action}" "${service_id}" "${mode}")"
  run_plan_write_json "${service_id}" "${action}" "${json}"
}
