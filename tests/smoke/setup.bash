#!/usr/bin/env bash
# Setup dry-run and project module smoke tests.

suite_setup() {
  local root output has_project_config_label has_setup_config_label has_old_yaml_label

  root="$(fixture_copy go-process-group)"
  assert_ok "setup --dry-run" \
    ops_run "${root}" setup --dry-run
  output="$(ops_run "${root}" setup --dry-run)"
  has_project_config_label=false
  has_setup_config_label=false
  has_old_yaml_label=false
  case "${output}" in
    *"Proposed project config services from discovery"*) has_project_config_label=true ;;
  esac
  case "${output}" in
    *"Proposed setup config from discovery"*) has_setup_config_label=true ;;
  esac
  case "${output}" in
    *"Proposed .ops.yaml services from discovery"*|*"Proposed .ops.yaml setup from discovery"*) has_old_yaml_label=true ;;
  esac
  assert_eq "setup preview uses project config services wording" "true" "${has_project_config_label}"
  assert_eq "setup preview uses setup config wording" "true" "${has_setup_config_label}"
  assert_eq "setup preview avoids old yaml proposal wording" "false" "${has_old_yaml_label}"

  root="$(fixture_copy go-process-group)"
  assert_ok "setup project --apply" \
    ops_run "${root}" setup project --apply
  assert_file_exists "setup project creates .gitignore" \
    "${root}/.ops.project/.gitignore"
  output="$(ops_run "${root}" setup show)"
  case "${output}" in
    *"Project config: .ops.project/config"*) assert_eq "setup show reports project config first" "true" "true" ;;
    *) assert_eq "setup show reports project config first" "true" "false" ;;
  esac
  case "${output}" in
    *"YAML compatibility export:"*) assert_eq "setup show labels yaml as compatibility export" "true" "true" ;;
    *) assert_eq "setup show labels yaml as compatibility export" "true" "false" ;;
  esac
  case "${output}" in
    *"Root config:"*) assert_eq "setup show avoids root config label" "false" "true" ;;
    *) assert_eq "setup show avoids root config label" "false" "false" ;;
  esac

  root="$(fixture_copy config-only)"
  assert_ok "setup run-plans preview" \
    ops_run "${root}" setup run-plans --actions=start,status
  assert_ok "setup run-plans apply" \
    ops_run "${root}" setup run-plans --apply --actions=start,status
  assert_file_exists "setup run-plans writes start plan" \
    "${root}/.ops.project/generated/run-plans/api.start.json"
  assert_file_exists "setup run-plans writes status plan" \
    "${root}/.ops.project/generated/run-plans/api.status.json"
  assert_jq_eq "run plan labels yaml as compatibility export" \
    '.project | has("compatibility_export")' \
    "${root}/.ops.project/generated/run-plans/api.start.json" "true"
  assert_jq_eq "run plan uses configured action label" \
    '.resolution.candidates | has("configured_action")' \
    "${root}/.ops.project/generated/run-plans/api.start.json" "true"

  root="$(fixture_copy config-only)"
  assert_ok "bootstrap --force applies config-first setup" \
    ops_run "${root}" bootstrap --force
  assert_file_exists "bootstrap writes services config" \
    "${root}/.ops.project/config/services.json"
  assert_eq "bootstrap does not create ops yaml" \
    "false" "$([[ -f "${root}/.ops.yaml" ]] && printf true || printf false)"

  root="$(fixture_copy config-only)"
  assert_ok "init applies config-first setup" \
    ops_run "${root}" init
  assert_file_exists "init writes services config" \
    "${root}/.ops.project/config/services.json"
  assert_eq "init does not create ops yaml" \
    "false" "$([[ -f "${root}/.ops.yaml" ]] && printf true || printf false)"

  root="$(fixture_copy config-only)"
  assert_ok "update --apply applies config-first setup" \
    ops_run "${root}" update --apply
  assert_file_exists "update writes services config" \
    "${root}/.ops.project/config/services.json"
  assert_eq "update does not create ops yaml" \
    "false" "$([[ -f "${root}/.ops.yaml" ]] && printf true || printf false)"

  root="$(fixture_copy config-only)"
  assert_ok "setup export-yaml --apply creates compatibility yaml" \
    ops_run "${root}" setup export-yaml --apply
  assert_file_exists "export-yaml writes ops yaml" \
    "${root}/.ops.yaml"

  rm -rf "${root}/.ops.project/config"
  assert_ok "setup import-yaml --apply recreates config" \
    ops_run "${root}" setup import-yaml --apply
  assert_file_exists "import-yaml writes services config" \
    "${root}/.ops.project/config/services.json"
}
