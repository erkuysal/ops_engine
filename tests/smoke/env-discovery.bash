#!/usr/bin/env bash
# Env file discovery smoke tests.

suite_env_discovery() {
  local root discovery_file

  root="$(fixture_copy env-service)"
  assert_ok "env-service discover --apply" \
    ops_run "${root}" setup discover --apply

  discovery_file="${root}/.ops.project/generated/discovery.json"
  assert_file_exists "discovery.json written" "${discovery_file}"
  assert_jq_eq "global env at project root" \
    '.global_env_files | join(",")' \
    "${discovery_file}" ".env"
  assert_jq_eq "backend discovers local env first" \
    '.directories[] | select(.path == "backend") | .env_files | join(",")' \
    "${discovery_file}" "backend/.env.local,backend/.env"

  assert_ok "setup --apply materializes env_files" \
    ops_run "${root}" setup --apply
  assert_jq_eq "services.json env_files" \
    '.services[] | select(.id == "backend") | .env_files | join(",")' \
    "${root}/.ops.project/config/services.json" "backend/.env.local,backend/.env"
  assert_jq_eq "project.json global_env_files" \
    '.global_env_files | join(",")' \
    "${root}/.ops.project/config/project.json" ".env"
}
