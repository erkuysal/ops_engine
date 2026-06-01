#!/usr/bin/env bash
# Runner profile inference smoke tests.

suite_runner_profiles() {
  local root

  root="$(fixture_copy go-process-group)"

  assert_ok "go process_group setup --apply" \
    ops_run "${root}" setup --apply

  assert_jq_eq "go backend runner kind is process_group" \
    '.services[] | select(.id == "backend") | .runner.kind' \
    "${root}/.ops.project/config/services.json" "process_group"

  root="$(fixture_copy docker-compose-app)"

  assert_ok "docker compose setup --apply" \
    ops_run "${root}" setup --apply

  assert_jq_eq "docker infra runner kind is compose" \
    '.services[] | select(.id == "infra") | .runner.kind' \
    "${root}/.ops.project/config/services.json" "compose"

  assert_jq_eq "docker infra role is docker_group" \
    '.services[] | select(.id == "infra") | .role' \
    "${root}/.ops.project/config/services.json" "docker_group"
}
