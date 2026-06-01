#!/usr/bin/env bash
# Validate smoke tests for config-only projects.

suite_validate() {
  local root

  root="$(fixture_copy config-only)"
  assert_ok "validate --plain passes" \
    ops_run "${root}" validate --plain

  root="$(fixture_copy node-vite)"
  assert_fail "validate without config fails" 2 \
    ops_run "${root}" validate --plain
}
