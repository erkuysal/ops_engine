#!/usr/bin/env bash
# Discovery smoke tests using stack fixtures.

suite_discovery() {
  local root discovery_file

  root="$(fixture_copy go-process-group)"
  assert_ok "go discover --apply" \
    ops_run "${root}" setup discover --apply
  discovery_file="${root}/.ops.project/generated/discovery.json"
  assert_file_exists "go discovery.json written" "${discovery_file}"
  assert_jq_eq "go backend role is process_group" \
    '.directories[] | select(.path == "backend") | .role' \
    "${discovery_file}" "process_group"
  assert_jq_eq "go backend is a service" \
    '.directories[] | select(.path == "backend") | .service' \
    "${discovery_file}" "true"

  root="$(fixture_copy node-vite)"
  assert_ok "node-vite discover --apply" \
    ops_run "${root}" setup discover --apply
  discovery_file="${root}/.ops.project/generated/discovery.json"
  assert_jq_eq "node-vite role is app" \
    '.directories[] | select(.path == "web") | .role' \
    "${discovery_file}" "app"

  root="$(fixture_copy node-workspace)"
  assert_ok "node-workspace discover --apply" \
    ops_run "${root}" setup discover --apply
  discovery_file="${root}/.ops.project/generated/discovery.json"
  assert_jq_eq "workspace root classified" \
    '.directories[] | select(.path == "frontend") | .role' \
    "${discovery_file}" "workspace_root"
  assert_jq_eq "workspace root not a service" \
    '.directories[] | select(.path == "frontend") | .service' \
    "${discovery_file}" "false"
  assert_jq_eq "child web package is app" \
    '.directories[] | select(.path == "frontend/web") | .role' \
    "${discovery_file}" "app"
}
