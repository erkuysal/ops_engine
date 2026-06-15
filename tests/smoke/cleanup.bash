#!/usr/bin/env bash
# Cleanup command smoke tests.

suite_cleanup() {
  local root

  root="$(fixture_copy config-only)"
  mkdir -p "${root}/.ops.project/run"
  printf '%s' "99999999" > "${root}/.ops.project/run/api.pid"

  assert_ok "cleanup previews stale pid" \
    ops_run "${root}" cleanup --pids
  assert_file_exists "cleanup preview keeps stale pid" \
    "${root}/.ops.project/run/api.pid"

  assert_ok "cleanup removes stale pid" \
    ops_run "${root}" cleanup --pids --apply
  if [[ -f "${root}/.ops.project/run/api.pid" ]]; then
    _harness_fail "cleanup apply removes stale pid" "pid file still exists"
  else
    _harness_pass "cleanup apply removes stale pid"
  fi
}
