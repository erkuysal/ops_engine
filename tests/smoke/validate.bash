#!/usr/bin/env bash
# Validate smoke tests for config-only projects.

suite_validate() {
  local root output

  root="$(fixture_copy config-only)"
  assert_ok "validate --plain passes" \
    ops_run "${root}" validate --plain
  output="$(ops_run "${root}" validate --plain)"
  case "${output}" in
    *"Source: .ops.project/config"*) assert_eq "validate reports config source" "true" "true" ;;
    *) assert_eq "validate reports config source" "true" "false" ;;
  esac
  assert_jq_eq "config fixture uses integer project version" '.version | type' \
    "${root}/.ops.project/config/project.json" "number"
  assert_jq_eq "config fixture uses integer services version" '.version | type' \
    "${root}/.ops.project/config/services.json" "number"
  assert_jq_eq "config fixture uses integer settings version" '.version | type' \
    "${root}/.ops.project/config/settings.json" "number"
  assert_jq_eq "config fixture uses integer profiles version" '.version | type' \
    "${root}/.ops.project/config/profiles.json" "number"
  case "${output}" in
    *"temporary manifest"*) assert_eq "validate avoids temporary manifest wording" "false" "true" ;;
    *) assert_eq "validate avoids temporary manifest wording" "false" "false" ;;
  esac

  jq '.version = "1"' "${root}/.ops.project/config/services.json" > "${root}/services.tmp"
  mv "${root}/services.tmp" "${root}/.ops.project/config/services.json"
  assert_ok "validate accepts legacy string config version" \
    ops_run "${root}" validate --plain
  output="$(ops_run "${root}" validate --plain)"
  case "${output}" in
    *'legacy string version "1"'*) assert_eq "validate warns about legacy string version" "true" "true" ;;
    *) assert_eq "validate warns about legacy string version" "true" "false" ;;
  esac

  jq '.version = 1' "${root}/.ops.project/config/services.json" > "${root}/services.tmp"
  mv "${root}/services.tmp" "${root}/.ops.project/config/services.json"

  assert_ok "export yaml for validate source preference" \
    ops_run "${root}" setup export-yaml --apply
  output="$(ops_run "${root}" validate --plain)"
  case "${output}" in
    *"Source: .ops.project/config"*) assert_eq "validate prefers config over yaml" "true" "true" ;;
    *) assert_eq "validate prefers config over yaml" "true" "false" ;;
  esac

  rm -rf "${root}/.ops.project/config"
  assert_ok "validate yaml compatibility fallback passes" \
    ops_run "${root}" validate --plain
  output="$(ops_run "${root}" validate --plain)"
  case "${output}" in
    *"Source: .ops.yaml compatibility manifest"*) assert_eq "validate reports yaml fallback source" "true" "true" ;;
    *) assert_eq "validate reports yaml fallback source" "true" "false" ;;
  esac

  root="$(fixture_copy node-vite)"
  assert_fail "validate without config fails" 2 \
    ops_run "${root}" validate --plain

  root="$(fixture_copy config-invalid)"
  assert_fail "validate rejects malformed config" 1 \
    ops_run "${root}" validate --plain
}
