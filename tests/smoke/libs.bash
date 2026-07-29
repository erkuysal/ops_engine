#!/usr/bin/env bash
# Unit-style tests for sourced library helpers.

suite_libs() {
  local root output precedence_output

  # cross_shell path detection
  OPS_PROJECT_ROOT="$(fixture_copy config-only)"
  export OPS_PROJECT_ROOT
  export OPS_CORE_ROOT="${OPS_CORE_ROOT}"
  # shellcheck source=/dev/null
  source "${OPS_CORE_ROOT}/lib/cross_shell.sh"

  HARNESS_TESTS_RUN=$((HARNESS_TESTS_RUN + 1))
  if is_windows_binary_path '/mnt/c/Windows/System32/go.exe'; then
    _harness_pass "is_windows_binary_path detects Windows path"
  else
    _harness_fail "is_windows_binary_path detects Windows path"
  fi

  HARNESS_TESTS_RUN=$((HARNESS_TESTS_RUN + 1))
  if ! is_windows_binary_path '/usr/bin/go'; then
    _harness_pass "is_windows_binary_path rejects Linux path"
  else
    _harness_fail "is_windows_binary_path rejects Linux path"
  fi

  HARNESS_TESTS_RUN=$((HARNESS_TESTS_RUN + 1))
  if ! is_windows_binary_path '/usr/local/go/bin/go'; then
    _harness_pass "is_windows_binary_path rejects native go path"
  else
    _harness_fail "is_windows_binary_path rejects native go path"
  fi

  root="$(fixture_copy config-only)"
  output="$(
    OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true bash -c '
      set -euo pipefail
      unset OPS_PROJECT_CONFIG_DIR OPS_PROJECT_CONFIG_SERVICES_FILE OPS_PROJECT_CONFIG_PROJECT_FILE
      unset OPS_PROJECT_CONFIG_SETTINGS_FILE OPS_PROJECT_CONFIG_PROFILES_FILE OPS_PROJECT_STATE_DIR
      source "${OPS_CORE_ROOT}/lib/init.sh"
      source "${OPS_CORE_ROOT}/lib/manifest.sh"
      project_require_config_or_yaml
      project_config_exists
      project_service_exists api
      printf "services=%s\n" "$(project_list_services | paste -sd "," -)"
      printf "stack=%s\n" "$(project_get_service_field api stack)"
      printf "path=%s\n" "$(project_get_service_field api path)"
      printf "env_count=%s\n" "$(project_global_env_file_count)"
    '
  )"
  case "${output}" in
    *"services=api"*) assert_eq "project aliases list config services" "true" "true" ;;
    *) assert_eq "project aliases list config services" "true" "false" ;;
  esac
  case "${output}" in
    *"stack=go"*) assert_eq "project aliases read service field" "true" "true" ;;
    *) assert_eq "project aliases read service field" "true" "false" ;;
  esac
  case "${output}" in
    *"path=backend"*) assert_eq "project aliases read service path" "true" "true" ;;
    *) assert_eq "project aliases read service path" "true" "false" ;;
  esac
  case "${output}" in
    *"env_count=0"*) assert_eq "project aliases read project env count" "true" "true" ;;
    *) assert_eq "project aliases read project env count" "true" "false" ;;
  esac

  root="$(fixture_copy config-only)"
  cat > "${root}/.ops.yaml" <<'YAML'
settings:
  start:
    mode: foreground
    healthcheck:
      wait: false
setup:
  default_profile: yaml-profile
profiles:
  local:
    remote:
      host: yaml-host
services:
  - id: yaml-only
    stack: custom
    path: yaml-only
YAML
  precedence_output="$(
    OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true bash -c '
      set -euo pipefail
      unset OPS_PROJECT_CONFIG_DIR OPS_PROJECT_CONFIG_SERVICES_FILE OPS_PROJECT_CONFIG_PROJECT_FILE
      unset OPS_PROJECT_CONFIG_SETTINGS_FILE OPS_PROJECT_CONFIG_PROFILES_FILE OPS_PROJECT_STATE_DIR
      source "${OPS_CORE_ROOT}/lib/init.sh"
      source "${OPS_CORE_ROOT}/lib/manifest.sh"
      source "${OPS_CORE_ROOT}/lib/settings.sh"
      source "${OPS_CORE_ROOT}/lib/setup.sh"
      printf "mode=%s\n" "$(ops_setting_mode ".start.mode" "foreground")"
      printf "health_wait=%s\n" "$(ops_setting_bool ".start.healthcheck.wait" "true")"
      printf "profile=%s\n" "$(setup_default_profile)"
      printf "profile_host=%s\n" "$(setup_profile_get local ".remote.host" "json-default")"
      if project_service_exists yaml-only; then printf "yaml_service=true\n"; else printf "yaml_service=false\n"; fi
    '
  )"
  case "${precedence_output}" in
    *"mode=background"*) assert_eq "JSON settings override conflicting YAML" "true" "true" ;;
    *) assert_eq "JSON settings override conflicting YAML" "true" "false" ;;
  esac
  case "${precedence_output}" in
    *"health_wait=true"*) assert_eq "missing JSON setting uses default without YAML fallback" "true" "true" ;;
    *) assert_eq "missing JSON setting uses default without YAML fallback" "true" "false" ;;
  esac
  case "${precedence_output}" in
    *"profile=local"*) assert_eq "missing JSON default profile does not fall back to YAML" "true" "true" ;;
    *) assert_eq "missing JSON default profile does not fall back to YAML" "true" "false" ;;
  esac
  case "${precedence_output}" in
    *"profile_host=json-default"*) assert_eq "missing JSON profile field uses caller default" "true" "true" ;;
    *) assert_eq "missing JSON profile field uses caller default" "true" "false" ;;
  esac
  case "${precedence_output}" in
    *"yaml_service=false"*) assert_eq "JSON service set does not fall through to YAML" "true" "true" ;;
    *) assert_eq "JSON service set does not fall through to YAML" "true" "false" ;;
  esac
}
