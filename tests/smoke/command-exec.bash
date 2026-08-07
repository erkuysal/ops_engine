#!/usr/bin/env bash
# Configured shell command transport and isolation tests.

suite_command_exec() {
  local root output_file
  root="$(fixture_copy configured-command)"
  output_file="${root}/service with spaces/command-output.txt"

  assert_ok "configured command preserves shell quoting" \
    ops_run "${root}" run verify quoted
  assert_file_exists "configured command writes output" "${output_file}"
  assert_eq "configured command preserves embedded quote and spaces" \
    "single'quote and spaces" "$(sed -n '1p' "${output_file}")"
  assert_eq "configured command preserves literal substitution text" \
    '$(not executed)' "$(sed -n '2p' "${output_file}")"
  assert_eq "configured command supports intentional substitution" \
    "substitution-ok" "$(sed -n '3p' "${output_file}")"
  assert_eq "configured command inherits exported ops context" \
    "quoted:verify" "$(sed -n '4p' "${output_file}")"

  assert_ok "configured multiline command survives transport" \
    ops_run "${root}" run multiline quoted
  assert_eq "configured multiline command executes once" \
    "line one" "$(sed -n '1p' "${root}/service with spaces/multiline-output.txt")"

  assert_fail "configured command failure maps to run failure" 5 \
    ops_run "${root}" run fail quoted
}
