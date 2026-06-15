#!/usr/bin/env bash
# Docker compose discovery/setup smoke tests.

suite_docker_compose() {
  local root discovery_file

  root="$(fixture_copy docker-compose-app)"
  assert_ok "docker compose discover --apply" \
    ops_run "${root}" setup discover --apply

  discovery_file="${root}/.ops.project/generated/discovery.json"
  assert_file_exists "docker discovery.json written" "${discovery_file}"
  assert_jq_eq "docker role is docker_group" \
    '.directories[] | select(.id == "infra") | .role' \
    "${discovery_file}" "docker_group"
  assert_jq_eq "docker compose files discovered" \
    '.directories[] | select(.id == "infra") | .compose_files | join(",")' \
    "${discovery_file}" "infra/docker-compose.yml"

  assert_ok "docker setup apply" \
    ops_run "${root}" setup --apply
  assert_jq_eq "services config keeps compose files" \
    '.services[] | select(.id == "infra") | .compose_files | join(",")' \
    "${root}/.ops.project/config/services.json" "infra/docker-compose.yml"

  root="$(fixture_copy node-vite)"
  assert_ok "node service compose discover --apply" \
    ops_run "${root}" setup discover --apply

  discovery_file="${root}/.ops.project/generated/discovery.json"
  assert_jq_eq "node service compose files discovered" \
    '.directories[] | select(.id == "web") | .compose_files | join(",")' \
    "${discovery_file}" "web/docker-compose.yml"

  assert_ok "node service compose setup --apply" \
    ops_run "${root}" setup --apply
  assert_jq_eq "node service config keeps compose files" \
    '.services[] | select(.id == "web") | .compose_files | join(",")' \
    "${root}/.ops.project/config/services.json" "web/docker-compose.yml"
}
