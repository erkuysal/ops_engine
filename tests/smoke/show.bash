#!/usr/bin/env bash
# Show (run-plan inspector) smoke tests.

suite_show() {
  local root output json

  root="$(fixture_copy config-only)"

  assert_ok "show <action> <service> exits 0" \
    ops_run "${root}" show start api

  output="$(ops_run "${root}" show start api)"
  case "${output}" in
    *"ops show start api"*) assert_eq "show prints a human plan header" "true" "true" ;;
    *) assert_eq "show prints a human plan header" "true" "false" ;;
  esac

  assert_fail "show rejects an unknown service" 2 \
    ops_run "${root}" show start not-a-real-service

  json="$(ops_run "${root}" show start api --json)"
  assert_eq "show --json emits the resolved run plan" "true" \
    "$(printf '%s' "${json}" | jq -e '
      .ok == true and .command == "show"
      and .service.id == "api"
      and .action.name == "start"
      and (.resolution.selected | has("strategy"))
      and (.run_plan_file | length) > 0
    ' >/dev/null 2>&1 && echo true || echo false)"
}
