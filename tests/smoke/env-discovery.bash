#!/usr/bin/env bash
# Env file discovery smoke tests.

suite_env_discovery() {
  local root discovery_file env_output

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
  assert_jq_eq "backend skips deployment env files" \
    '.directories[] | select(.path == "backend") | .env_files | index("backend/.env.staging") == null' \
    "${discovery_file}" "true"
  assert_jq_eq "backend skips production env files" \
    '.directories[] | select(.path == "backend") | .env_files | index("backend/.env.production") == null' \
    "${discovery_file}" "true"

  assert_ok "setup --apply materializes env_files" \
    ops_run "${root}" setup --apply
  assert_jq_eq "services.json env_files" \
    '.services[] | select(.id == "backend") | .env_files | join(",")' \
    "${root}/.ops.project/config/services.json" "backend/.env.local,backend/.env"
  assert_jq_eq "project.json global_env_files" \
    '.global_env_files | join(",")' \
    "${root}/.ops.project/config/project.json" ".env"

  env_output="$(ops_run "${root}" env show backend --unmask)"
  local has_global_env=false has_service_env=false
  case "${env_output}" in
    *"ROOT_ENV"*"global:.env"*) has_global_env=true ;;
  esac
  case "${env_output}" in
    *"SERVICE_LOCAL"*"service:backend/.env.local"*|*"SERVICE_ENV"*"service:backend/.env"*) has_service_env=true ;;
  esac
  assert_eq "env show loads project global env from config" "true" "${has_global_env}"
  assert_eq "env show loads service env from config" "true" "${has_service_env}"

  root="$(fixture_copy env-service)"
  assert_ok "env-service staging discover --apply" \
    ops_run "${root}" setup discover --profile=staging --apply
  discovery_file="${root}/.ops.project/generated/discovery.json"
  assert_jq_eq "staging profile includes staging env" \
    '.directories[] | select(.path == "backend") | .env_files | join(",")' \
    "${discovery_file}" "backend/.env.local,backend/.env,backend/.env.staging"
  assert_jq_eq "staging profile still skips production env" \
    '.directories[] | select(.path == "backend") | .env_files | index("backend/.env.production") == null' \
    "${discovery_file}" "true"

  assert_ok "env-service staging setup --apply" \
    ops_run "${root}" setup --profile=staging --apply
  assert_jq_eq "staging services.json env_files" \
    '.services[] | select(.id == "backend") | .env_files | join(",")' \
    "${root}/.ops.project/config/services.json" "backend/.env.local,backend/.env,backend/.env.staging"

  root="$(fixture_copy env-service)"
  assert_ok "env-service staging discover supports profile space form" \
    ops_run "${root}" setup discover --profile staging --apply
  discovery_file="${root}/.ops.project/generated/discovery.json"
  assert_jq_eq "profile space form includes staging env" \
    '.directories[] | select(.path == "backend") | .env_files | join(",")' \
    "${discovery_file}" "backend/.env.local,backend/.env,backend/.env.staging"

  root="$(fixture_copy env-service)"
  assert_ok "env-service local setup before profile switch" \
    ops_run "${root}" setup --apply
  assert_ok "env-service setup switches to staging profile" \
    ops_run "${root}" setup --profile=staging --apply
  assert_jq_eq "staging setup appends staging env over existing local config" \
    '.services[] | select(.id == "backend") | .env_files | join(",")' \
    "${root}/.ops.project/config/services.json" "backend/.env.local,backend/.env,backend/.env.staging"

  root="$(fixture_copy env-service)"
  assert_ok "env-service production discover --apply" \
    ops_run "${root}" setup discover --profile=production --apply
  discovery_file="${root}/.ops.project/generated/discovery.json"
  assert_jq_eq "production profile includes production env" \
    '.directories[] | select(.path == "backend") | .env_files | join(",")' \
    "${discovery_file}" "backend/.env.local,backend/.env,backend/.env.production"
  assert_jq_eq "production profile skips staging env" \
    '.directories[] | select(.path == "backend") | .env_files | index("backend/.env.staging") == null' \
    "${discovery_file}" "true"
}
