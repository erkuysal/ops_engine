#!/usr/bin/env bash
# Unit-style tests for sourced library helpers.

suite_libs() {
  local root output

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
}
