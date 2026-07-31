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

  root="$(fixture_copy workspace-root-compose)"
  assert_ok "workspace root compose setup preview" \
    ops_run "${root}" setup --dry-run
  assert_ok "workspace root compose setup apply" \
    ops_run "${root}" setup --apply

  discovery_file="${root}/.ops.project/generated/discovery.json"
  assert_jq_eq "root compose service uses normalized project name" \
    '.directories[] | select(.path == ".") | .id' \
    "${discovery_file}" "hemak"
  assert_jq_eq "root compose service is docker group" \
    '.services[] | select(.path == ".") | [.stack,.role,.runner.kind] | join(",")' \
    "${root}/.ops.project/config/services.json" "docker,docker_group,compose"
  assert_jq_eq "root compose keeps base and production files" \
    '.services[] | select(.path == ".") | .compose_files | join(",")' \
    "${root}/.ops.project/config/services.json" "docker-compose.yml,deployment/compose/production.yml"
  assert_jq_eq "workspace discovers root and node development services" \
    '[.services[].id] | sort | join(",")' \
    "${root}/.ops.project/config/services.json" "backend,frontend,hemak"
  assert_jq_eq "frontend depends on backend" \
    '.services[] | select(.id == "frontend") | .depends_on | join(",")' \
    "${root}/.ops.project/config/services.json" "backend"
}
