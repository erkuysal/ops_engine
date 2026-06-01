#!/usr/bin/env bash
# Setup dry-run and project module smoke tests.

suite_setup() {
  local root

  root="$(fixture_copy go-process-group)"
  assert_ok "setup --dry-run" \
    ops_run "${root}" setup --dry-run

  root="$(fixture_copy go-process-group)"
  assert_ok "setup project --apply" \
    ops_run "${root}" setup project --apply
  assert_file_exists "setup project creates .gitignore" \
    "${root}/.ops.project/.gitignore"
}
