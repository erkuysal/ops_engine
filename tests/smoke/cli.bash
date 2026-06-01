#!/usr/bin/env bash
# CLI smoke tests: version, help, unknown command.

suite_cli() {
  local root
  root="$(fixture_copy config-only)"

  assert_ok "version exits 0" \
    ops_run "${root}" version

  assert_ok "help exits 0" \
    ops_run "${root}" help

  assert_fail "unknown command exits 1" 1 \
    ops_run "${root}" not-a-command
}
