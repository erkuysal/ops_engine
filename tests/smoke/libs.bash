#!/usr/bin/env bash
# Unit-style tests for sourced library helpers.

suite_libs() {
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
}
