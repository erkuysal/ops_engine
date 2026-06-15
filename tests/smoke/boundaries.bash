#!/usr/bin/env bash
# Package boundary smoke tests.

suite_boundaries() {
  local root
  root="$(fixture_copy config-only)"

  assert_ok "boundary doctor exits 0" \
    ops_run "${root}" doctor boundaries
}
