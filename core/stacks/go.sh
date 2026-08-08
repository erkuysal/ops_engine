#!/usr/bin/env bash
# .ops-core/stacks/go.sh - Go stack strategy.

set -euo pipefail

_GO_STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/init.sh
source "${_GO_STACK_DIR}/../lib/init.sh"
# shellcheck source=../lib/cross_shell.sh
source "${_GO_STACK_DIR}/../lib/cross_shell.sh"
# shellcheck source=../lib/command_exec.sh
source "${_GO_STACK_DIR}/../lib/command_exec.sh"
# shellcheck source=../lib/manifest.sh
source "${_GO_STACK_DIR}/../lib/manifest.sh"

_go_service_value() {
  local expr="${1:?service field required}"
  local field="${expr#.}"
  project_get_service_field "${OPS_SERVICE_ID}" "${field}" 2>/dev/null || true
}

_go_runner_kind() {
  _go_service_value '.runner.kind'
}

_go_is_process_group() {
  [[ "$(_go_runner_kind)" == "process_group" ]]
}

_go_output_dir() {
  local configured
  configured="$(_go_service_value '.build.output_dir')"
  if [[ -n "${configured}" && "${configured}" != "null" ]]; then
    case "${configured}" in
      /*) printf '%s' "${configured}" ;;
      *)  printf '%s/%s' "${OPS_PROJECT_ROOT}" "${configured}" ;;
    esac
  else
    printf '%s/generated/bin/%s' "${OPS_PROJECT_STATE_DIR:-${OPS_PROJECT_ROOT}/.ops.project}" "${OPS_SERVICE_ID}"
  fi
}

_go_target_arch() {
  local arch
  arch="$(_go_service_value '.build.target_arch')"
  printf '%s' "${arch:-amd64}"
}

_go_process_names() {
  project_get_service_list_field "${OPS_SERVICE_ID}" "run.processes.name" 2>/dev/null || true
}

_go_build_output_names() {
  project_get_service_list_field "${OPS_SERVICE_ID}" "build.outputs.name" 2>/dev/null || true
}

_go_build_output_package() {
  local name="$1"
  project_get_service_json_field "${OPS_SERVICE_ID}" build.outputs '[]' \
    | jq -r --arg name "${name}" '.[]? | select(.name == $name) | .package // ""' 2>/dev/null || true
}

_go_process_command() {
  local name="$1"
  project_get_service_json_field "${OPS_SERVICE_ID}" run.processes '[]' \
    | jq -r --arg name "${name}" '.[]? | select(.name == $name) | .command // ""' 2>/dev/null || true
}

_go_log_dir() {
  printf '%s/%s' "${OPS_PROJECT_LOG_DIR:-${OPS_PROJECT_ROOT}/.ops.project/logs}" "${OPS_SERVICE_ID}"
}

_go_run_dir() {
  printf '%s/%s' "${OPS_PROJECT_RUN_DIR:-${OPS_PROJECT_ROOT}/.ops.project/run}" "${OPS_SERVICE_ID}"
}

_go_build_one() {
  local output="$1"
  local package="$2"
  mkdir -p "$(dirname "${output}")"

  if [[ "$(tool_host_os go)" == "windows" && "$(shell_host_os)" == "wsl" ]]; then
    printf '[INFO] Go build via Windows Go cross-compile: %s -> %s\n' "${package}" "${output}"
    windows_go_build_linux "${output}" "${package}" "$(_go_target_arch)"
  else
    printf '[INFO] Go build native: %s -> %s\n' "${package}" "${output}"
    run_cross_shell_binary go build -o "${output}" "${package}" < /dev/null
  fi
  chmod +x "${output}" 2>/dev/null || true
}

_go_build_process_group() {
  local out_dir name package any=false
  out_dir="$(_go_output_dir)"
  mkdir -p "${out_dir}"

  while IFS= read -r name; do
    [[ -z "${name}" || "${name}" == "null" ]] && continue
    package="$(_go_build_output_package "${name}")"
    [[ -n "${package}" && "${package}" != "null" ]] || continue
    any=true
    _go_build_one "${out_dir}/${name}" "${package}"
  done < <(_go_build_output_names)

  [[ "${any}" == "true" ]] || {
    printf '[ERROR] Go process group has no build.outputs entries for %s\n' "${OPS_SERVICE_ID}" >&2
    return 2
  }
}

_go_process_group_needs_build() {
  local out_dir name
  out_dir="$(_go_output_dir)"
  while IFS= read -r name; do
    [[ -z "${name}" || "${name}" == "null" ]] && continue
    [[ ! -x "${out_dir}/${name}" ]] && return 0
  done < <(_go_build_output_names)
  return 1
}

_go_start_process() {
  local name="$1"
  local command="$2"
  local log_dir run_dir pid_file log_file
  log_dir="$(_go_log_dir)"
  run_dir="$(_go_run_dir)"
  pid_file="${run_dir}/${name}.pid"
  log_file="${log_dir}/${name}.log"
  mkdir -p "${log_dir}" "${run_dir}"

  if [[ -f "${pid_file}" ]]; then
    local old_pid
    old_pid="$(cat "${pid_file}" 2>/dev/null || true)"
    if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
      printf '[INFO] %s is already running (PID %s)\n' "${name}" "${old_pid}"
      return 0
    fi
    rm -f "${pid_file}"
  fi

  printf '[INFO] Starting %s: %s\n' "${name}" "${command}"
  nohup bash -c "${command}" > "${log_file}" 2>&1 < /dev/null &
  local pid=$!
  echo "${pid}" > "${pid_file}"
  sleep 0.3
  if kill -0 "${pid}" 2>/dev/null; then
    printf '[OK] %s started (PID %s, log %s)\n' "${name}" "${pid}" "${log_file#${OPS_PROJECT_ROOT}/}"
    return 0
  fi
  printf '[ERROR] %s failed to start; log follows:\n' "${name}" >&2
  cat "${log_file}" >&2 2>/dev/null || true
  return 5
}

_go_start_process_group() {
  local out_dir name command any=false
  if _go_process_group_needs_build; then
    _go_build_process_group
  fi

  out_dir="$(_go_output_dir)"
  while IFS= read -r name; do
    [[ -z "${name}" || "${name}" == "null" ]] && continue
    any=true
    command="$(_go_process_command "${name}")"
    [[ -n "${command}" && "${command}" != "null" ]] || command="${out_dir}/${name}"
    _go_start_process "${name}" "${command}"
  done < <(_go_process_names)

  [[ "${any}" == "true" ]] || {
    printf '[ERROR] Go process group has no run.processes entries for %s\n' "${OPS_SERVICE_ID}" >&2
    return 2
  }

  if [[ "${OPS_RUN_MODE:-foreground}" == "foreground" ]]; then
    _go_follow_process_group_logs
  fi
}

_go_follow_process_group_logs() {
  local log_dir name log_files=()
  log_dir="$(_go_log_dir)"

  printf '\n[INFO] Following %s logs (Ctrl+C to detach, services continue running):\n' "${OPS_SERVICE_ID}"
  printf '%s\n' '-----------------------------------------------'

  while IFS= read -r name; do
    [[ -z "${name}" || "${name}" == "null" ]] && continue
    log_files+=("${log_dir}/${name}.log")
  done < <(_go_process_names)

  [[ ${#log_files[@]} -gt 0 ]] || return 0

  local waited=0
  while [[ ! -f "${log_files[0]}" && ${waited} -lt 10 ]]; do
    sleep 0.3
    waited=$((waited + 1))
  done

  tail -F "${log_files[@]}" 2>/dev/null || true
}

_go_stop_process_group() {
  local run_dir name pid_file pid stopped=false
  run_dir="$(_go_run_dir)"
  while IFS= read -r name; do
    [[ -z "${name}" || "${name}" == "null" ]] && continue
    pid_file="${run_dir}/${name}.pid"
    if [[ -f "${pid_file}" ]]; then
      pid="$(cat "${pid_file}" 2>/dev/null || true)"
      if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        printf '[INFO] Stopping %s (PID %s)\n' "${name}" "${pid}"
        kill "${pid}" 2>/dev/null || true
        stopped=true
      fi
      rm -f "${pid_file}"
    fi
  done < <(_go_process_names)
  [[ "${stopped}" == "true" ]] && printf '[OK] Process group stopped\n' || printf '[INFO] Process group is not running\n'
}

_go_status_process_group() {
  local run_dir name pid_file pid any=false all=true
  run_dir="$(_go_run_dir)"
  while IFS= read -r name; do
    [[ -z "${name}" || "${name}" == "null" ]] && continue
    any=true
    pid_file="${run_dir}/${name}.pid"
    if [[ ! -f "${pid_file}" ]]; then
      all=false
      continue
    fi
    pid="$(cat "${pid_file}" 2>/dev/null || true)"
    if [[ -z "${pid}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
      rm -f "${pid_file}"
      all=false
    fi
  done < <(_go_process_names)
  [[ "${any}" == "true" && "${all}" == "true" ]]
}

go_dispatch() {
  local action="${1:-}"
  local explicit_cmd="${2:-}"

  if [[ -n "${explicit_cmd}" && "${explicit_cmd}" != "null" ]]; then
    ops_run_configured_command "${explicit_cmd}"
    return $?
  fi

  case "${action}" in
    start)
      if _go_is_process_group; then
        _go_start_process_group
        return $?
      fi
      run_cross_shell_binary go run main.go
      return $?
      ;;
    build)
      if _go_is_process_group; then
        _go_build_process_group
        return $?
      fi
      run_cross_shell_binary go build -o app
      return $?
      ;;
    test)
      run_cross_shell_binary go test ./...
      return $?
      ;;
    stop)
      if _go_is_process_group; then
        _go_stop_process_group
        return $?
      fi
      local pid_file="${OPS_PROJECT_RUN_DIR:-${OPS_PROJECT_ROOT}/.ops.project/run}/${OPS_SERVICE_ID}.pid"
      if [[ -f "${pid_file}" ]]; then
        local pid
        pid="$(cat "${pid_file}")"
        if kill -0 "${pid}" 2>/dev/null; then
          kill "${pid}" || true
        fi
        rm -f "${pid_file}"
      fi
      return 0
      ;;
    status)
      if _go_is_process_group; then
        _go_status_process_group
        return $?
      fi
      local pid_file="${OPS_PROJECT_RUN_DIR:-${OPS_PROJECT_ROOT}/.ops.project/run}/${OPS_SERVICE_ID}.pid"
      if [[ -f "${pid_file}" ]]; then
        local pid
        pid="$(cat "${pid_file}")"
        if kill -0 "${pid}" 2>/dev/null; then
          return 0
        fi
        rm -f "${pid_file}"
      fi
      return 1
      ;;
    *)
      return 10
      ;;
  esac
}
