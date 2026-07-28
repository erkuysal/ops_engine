#!/usr/bin/env bash
# Shipping setup inference/materialization smoke tests.

suite_setup_shipping() {
  local root json output config
  root="$(fixture_copy container-pipeline)"
  config="${root}/.ops.project/config/shipping.json"
  rm -f "${config}"

  json="$(ops_run "${root}" setup shipping --refresh --json)"
  assert_eq "shipping setup infers a pipeline" "local" "$(jq -r '.default_pipeline' <<< "${json}")"
  assert_eq "shipping setup discovers compose config" "infra/docker-compose.yml" "$(jq -r '.pipelines.local.jobs[0].compose_files[0]' <<< "${json}")"
  assert_eq "shipping setup preview does not write config" "false" "$([[ -f "${config}" ]] && printf true || printf false)"

  output="$(ops_run "${root}" setup shipping --refresh --apply)"
  assert_file_exists "shipping setup apply writes project config" "${config}"
  assert_eq "shipping setup marks generated source" "ops_setup_shipping" "$(jq -r '.source' "${config}")"
  case "${output}" in
    *"Wrote .ops.project/config/shipping.json"*) assert_eq "shipping setup apply reports output" "true" "true" ;;
    *) assert_eq "shipping setup apply reports output" "true" "false" ;;
  esac

  json="$(ops_run "${root}" ship --json)"
  assert_eq "generated shipping config is consumable" "docker.compose" "$(jq -r '.jobs[0].uses' <<< "${json}")"
}
