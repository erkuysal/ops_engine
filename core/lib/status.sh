#!/usr/bin/env bash
# .ops/core/lib/status.sh — Service runtime status from PID files and config.

set -euo pipefail
if [[ "${_OPS_CORE_STATUS_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_STATUS_LOADED=1

# shellcheck source=manifest.sh
source "${OPS_CORE_ROOT}/lib/manifest.sh"
# shellcheck source=setup.sh
source "${OPS_CORE_ROOT}/lib/setup.sh"

status_config_source_rel() {
  if project_config_services_exists; then
    printf '%s' "${OPS_PROJECT_CONFIG_SERVICES_FILE#${OPS_PROJECT_ROOT}/}"
  else
    printf '%s' ".ops.yaml"
  fi
}

status_pid_is_alive() {
  local pid="${1:-}"
  [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

status_read_pid_file() {
  local pid_file="${1:?status_read_pid_file: pid file required}"
  local pid=""
  [[ -f "${pid_file}" ]] || return 1
  pid="$(tr -d '[:space:]' < "${pid_file}" 2>/dev/null || true)"
  status_pid_is_alive "${pid}" || return 1
  printf '%s' "${pid}"
}

status_is_process_group() {
  local svc_id="${1:?status_is_process_group: service id required}"
  [[ "$(project_get_service_field "${svc_id}" "runner.kind")" == "process_group" ]]
}

status_service_port() {
  local svc_id="$1"
  local port="0"
  if project_config_services_exists; then
    require_bins jq
    port="$(jq -r --arg id "${svc_id}" '.services[]? | select(.id == $id) | .setup.port // 0' \
      "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || printf '0')"
  else
    port="$(setup_service_get "${svc_id}" port "0")"
  fi
  [[ -z "${port}" || "${port}" == "null" ]] && port="0"
  printf '%s' "${port}"
}

status_service_healthcheck() {
  local svc_id="$1"
  project_get_service_field "${svc_id}" healthcheck
}

status_service_compose_files() {
  local svc_id="$1"
  project_get_service_list_field "${svc_id}" compose_files
}

status_docker_running() {
  local svc_id="$1" svc_path="$2"
  local abs="${OPS_PROJECT_ROOT}/${svc_path}"
  local compose_files=() file compose_args=()
  [[ -d "${abs}" ]] || return 1
  command -v docker >/dev/null 2>&1 || return 1

  while IFS= read -r file; do
    [[ -n "${file}" && "${file}" != "null" ]] && compose_files+=("${file}")
  done < <(status_service_compose_files "${svc_id}")

  if [[ ${#compose_files[@]} -eq 0 ]]; then
    for file in compose.yml compose.yaml docker-compose.yml docker-compose.yaml; do
      [[ -f "${abs}/${file}" ]] && compose_files+=("${file}")
    done
  fi
  [[ ${#compose_files[@]} -gt 0 ]] || return 1
  for file in "${compose_files[@]}"; do
    compose_args+=(-f "${file}")
  done

  (
    cd "${abs}"
    docker compose "${compose_args[@]}" ps --services --filter "status=running" 2>/dev/null | grep -q .
  )
}

# Internal field separator for process rows (name, pid, pid_file).
_STATUS_FS=$'\x1f'

# Collect process rows as: name<FS>pid<FS>pid_file_rel
status_collect_process_rows() {
  local svc_id="${1:?status_collect_process_rows: service id required}"
  local stack path run_dir pid_file rel pid name runner_kind

  stack="$(project_get_service_field "${svc_id}" stack)"
  path="$(project_get_service_field "${svc_id}" path)"
  runner_kind="$(project_get_service_field "${svc_id}" runner.kind 2>/dev/null || true)"

  if [[ "${runner_kind}" == "compose" || "${stack}" == "docker" ]]; then
    if status_docker_running "${svc_id}" "${path}"; then
      local compose_rel
      compose_rel="$(status_service_compose_files "${svc_id}" | head -n 1)"
      [[ -z "${compose_rel}" ]] && compose_rel="${path}/docker-compose.yml"
      printf '%s%s%s%s%s\n' "compose" "${_STATUS_FS}" "docker" "${_STATUS_FS}" "${compose_rel}"
    fi
    return 0
  fi

  if status_is_process_group "${svc_id}"; then
    run_dir="${OPS_PROJECT_RUN_DIR}/${svc_id}"
    while IFS= read -r name; do
      [[ -z "${name}" || "${name}" == "null" ]] && continue
      pid_file="${run_dir}/${name}.pid"
      rel="${pid_file#${OPS_PROJECT_ROOT}/}"
      if pid="$(status_read_pid_file "${pid_file}" 2>/dev/null)"; then
        printf '%s%s%s%s%s\n' "${name}" "${_STATUS_FS}" "${pid}" "${_STATUS_FS}" "${rel}"
      else
        [[ -f "${pid_file}" ]] && rm -f "${pid_file}" 2>/dev/null || true
        printf '%s%s%s%s%s\n' "${name}" "${_STATUS_FS}" "" "${_STATUS_FS}" "${rel}"
      fi
    done < <(project_get_service_list_field "${svc_id}" "run.processes.name")

    if [[ -d "${run_dir}" ]]; then
      local stale
      for stale in "${run_dir}"/*.pid; do
        [[ -f "${stale}" ]] || continue
        name="$(basename "${stale}" .pid)"
        if ! project_get_service_list_field "${svc_id}" "run.processes.name" | grep -qxF "${name}"; then
          rel="${stale#${OPS_PROJECT_ROOT}/}"
          if pid="$(status_read_pid_file "${stale}" 2>/dev/null)"; then
            printf '%s%s%s%s%s\n' "${name}" "${_STATUS_FS}" "${pid}" "${_STATUS_FS}" "${rel}"
          fi
        fi
      done
    fi
    return 0
  fi

  pid_file="${OPS_PROJECT_RUN_DIR}/${svc_id}.pid"
  rel="${pid_file#${OPS_PROJECT_ROOT}/}"
  if pid="$(status_read_pid_file "${pid_file}" 2>/dev/null)"; then
    printf '%s%s%s%s%s\n' "${svc_id}" "${_STATUS_FS}" "${pid}" "${_STATUS_FS}" "${rel}"
  else
    [[ -f "${pid_file}" ]] && rm -f "${pid_file}" 2>/dev/null || true
    printf '%s%s%s%s%s\n' "${svc_id}" "${_STATUS_FS}" "" "${_STATUS_FS}" "${rel}"
  fi
}

_status_parse_row() {
  local row="$1"
  _STATUS_ROW_NAME="${row%%"${_STATUS_FS}"*}"
  local rest="${row#*"${_STATUS_FS}"}"
  _STATUS_ROW_PID="${rest%%"${_STATUS_FS}"*}"
  _STATUS_ROW_FILE="${rest#*"${_STATUS_FS}"}"
}

# Print aggregate state: running | partial | stopped | unknown
status_aggregate_state() {
  local svc_id="$1"
  local stack path runner_kind
  stack="$(project_get_service_field "${svc_id}" stack)"
  path="$(project_get_service_field "${svc_id}" path)"
  runner_kind="$(project_get_service_field "${svc_id}" runner.kind 2>/dev/null || true)"

  if [[ "${runner_kind}" == "compose" || "${stack}" == "docker" ]]; then
    if status_docker_running "${svc_id}" "${path}"; then
      printf 'running'
    else
      printf 'stopped'
    fi
    return 0
  fi

  local rows=() row alive_count=0 total=0
  while IFS= read -r row; do
    [[ -z "${row}" ]] && continue
    rows+=("${row}")
  done < <(status_collect_process_rows "${svc_id}")

  if [[ ${#rows[@]} -eq 0 ]]; then
    printf 'stopped'
    return 0
  fi

  for row in "${rows[@]}"; do
    _status_parse_row "${row}"
    total=$((total + 1))
    if [[ -n "${_STATUS_ROW_PID}" ]]; then
      alive_count=$((alive_count + 1))
    fi
  done

  if [[ "${alive_count}" -eq 0 ]]; then
    printf 'stopped'
  elif [[ "${alive_count}" -eq "${total}" ]]; then
    printf 'running'
  else
    printf 'partial'
  fi
}

status_format_pids() {
  local svc_id="$1"
  local parts=() row
  while IFS= read -r row; do
    [[ -z "${row}" ]] && continue
    _status_parse_row "${row}"
    [[ -z "${_STATUS_ROW_PID}" ]] && continue
    if status_is_process_group "${svc_id}" && [[ -n "${_STATUS_ROW_NAME}" ]]; then
      parts+=("${_STATUS_ROW_NAME}:${_STATUS_ROW_PID}")
    else
      parts+=("${_STATUS_ROW_PID}")
    fi
  done < <(status_collect_process_rows "${svc_id}")
  local IFS=,
  printf '%s' "${parts[*]:-}"
}

status_service_json() {
  local svc_id="${1:?status_service_json: service id required}"
  require_bins jq

  local name stack path state port health pids config_source
  name="$(project_get_service_field "${svc_id}" name)"
  stack="$(project_get_service_field "${svc_id}" stack)"
  path="$(project_get_service_field "${svc_id}" path)"
  state="$(status_aggregate_state "${svc_id}")"
  port="$(status_service_port "${svc_id}")"
  health="$(status_service_healthcheck "${svc_id}")"
  pids="$(status_format_pids "${svc_id}")"
  config_source="$(status_config_source_rel)"

  local processes_json='[]'
  local row proc_name proc_pid proc_file alive_json
  while IFS= read -r row; do
    [[ -z "${row}" ]] && continue
    _status_parse_row "${row}"
    proc_name="${_STATUS_ROW_NAME}"
    proc_pid="${_STATUS_ROW_PID}"
    proc_file="${_STATUS_ROW_FILE}"
    alive_json="false"
    [[ -n "${proc_pid}" ]] && alive_json="true"
    processes_json="$(jq \
      --arg name "${proc_name}" \
      --arg pid "${proc_pid}" \
      --arg pid_file "${proc_file}" \
      --argjson alive "${alive_json}" \
      '. + [{
        name: $name,
        pid: (if ($pid | length) > 0 then (try ($pid | tonumber) catch $pid) else null end),
        pid_file: $pid_file,
        alive: $alive
      }]' \
      <<< "${processes_json}")"
  done < <(status_collect_process_rows "${svc_id}")

  jq -n \
    --arg id "${svc_id}" \
    --arg name "${name}" \
    --arg stack "${stack}" \
    --arg path "${path}" \
    --arg state "${state}" \
    --arg pids "${pids}" \
    --arg port "${port}" \
    --arg healthcheck "${health}" \
    --arg config_source "${config_source}" \
    --argjson processes "${processes_json}" \
    '{
      id: $id,
      name: $name,
      stack: $stack,
      path: $path,
      state: $state,
      pids: $pids,
      port: (if ($port | test("^[0-9]+$")) then ($port | tonumber) else 0 end),
      healthcheck: $healthcheck,
      config_source: $config_source,
      processes: $processes
    }'
}

status_all_json() {
  local ids=() id services_json='[]'
  mapfile -t ids < <(project_list_services)

  for id in "${ids[@]+"${ids[@]}"}"; do
    [[ -z "${id}" ]] && continue
    services_json="$(jq --argjson svc "$(status_service_json "${id}")" '. + [$svc]' <<< "${services_json}")"
  done

  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --arg config_source "$(status_config_source_rel)" \
    --argjson services "${services_json}" \
    '{
      version: 1,
      generated_at: $generated_at,
      config_source: $config_source,
      services: $services
    }'
}

return 0
