#!/usr/bin/env bash
# Doctor smoke tests against a minimal fixture project.

suite_doctor() {
  local root output
  root="$(fixture_copy config-only)"

  assert_ok "doctor exits 0" \
    ops_run "${root}" doctor
  output="$(ops_run "${root}" doctor)"
  case "${output}" in
    *".ops.project/config/services.json exists"*) assert_eq "doctor reports project config" "true" "true" ;;
    *) assert_eq "doctor reports project config" "true" "false" ;;
  esac
  case "${output}" in
    *".ops.yaml compatibility export not present (optional)"*) assert_eq "doctor treats missing yaml as optional" "true" "true" ;;
    *) assert_eq "doctor treats missing yaml as optional" "true" "false" ;;
  esac
  case "${output}" in
    *"ops experimental init"*|*".ops.yaml not yet created"*) assert_eq "doctor avoids legacy yaml init warning" "false" "true" ;;
    *) assert_eq "doctor avoids legacy yaml init warning" "false" "false" ;;
  esac

  local json
  json="$(ops_run "${root}" doctor --json)"
  assert_eq "doctor --json emits pure JSON" "true" \
    "$(printf '%s' "${json}" | jq -e '.ok == true and .command == "doctor" and (.checks | type) == "array" and .summary.failed == 0' >/dev/null 2>&1 && echo true || echo false)"
}
