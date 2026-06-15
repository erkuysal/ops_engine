#!/usr/bin/env bash
# Status command smoke tests.

suite_status() {
  local root json output

  root="$(fixture_copy config-only)"
  assert_ok "status all services" \
    ops_run "${root}" status --plain
  output="$(ops_run "${root}" status --plain)"
  case "${output}" in
    *"project config source: .ops.project/config/services.json"*) assert_eq "status labels project config source" "true" "true" ;;
    *) assert_eq "status labels project config source" "true" "false" ;;
  esac
  assert_ok "status single service" \
    ops_run "${root}" status api --plain
  assert_ok "ps alias" \
    ops_run "${root}" ps --plain

  root="$(fixture_copy config-only)"
  json="$(OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" status api --json)"
  assert_eq "status json state stopped" "stopped" "$(jq -r '.state' <<< "${json}")"
  assert_eq "status json config source" ".ops.project/config/services.json" "$(jq -r '.config_source' <<< "${json}")"

  root="$(fixture_copy config-only)"
  mkdir -p "${root}/.ops.project/run"
  printf '%s' "$$" > "${root}/.ops.project/run/api.pid"
  json="$(OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" status api --json)"
  assert_eq "status json state running" "running" "$(jq -r '.state' <<< "${json}")"
  assert_eq "status json pid alive" "true" "$(jq -r '.processes[0].alive' <<< "${json}")"

  root="$(fixture_copy go-process-group-config)"
  mkdir -p "${root}/.ops.project/run/backend"
  printf '%s' "$$" > "${root}/.ops.project/run/backend/api.pid"
  json="$(OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" status backend --json)"
  assert_eq "process group partial state" "partial" "$(jq -r '.state' <<< "${json}")"
}
