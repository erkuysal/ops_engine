#!/usr/bin/env bash
# Doctor smoke tests against a minimal fixture project.

suite_doctor() {
  local root
  root="$(fixture_copy config-only)"

  assert_ok "doctor exits 0" \
    ops_run "${root}" doctor
}
