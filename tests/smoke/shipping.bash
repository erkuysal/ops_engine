#!/usr/bin/env bash
# Unified shipping plan smoke tests.

suite_shipping() {
  local root json output
  root="$(fixture_copy container-pipeline)"

  json="$(ops_run "${root}" ship --tag=test123 --json)"
  assert_eq "ship chooses configured default pipeline" "production" "$(jq -r '.pipeline' <<< "${json}")"
  assert_eq "ship includes all four driver kinds" "4" "$(jq '[.jobs[].uses] | unique | length' <<< "${json}")"
  assert_eq "ship plans compose build" "1" "$(jq '[.actions[] | select(.operation == "docker.compose.build" and .selected)] | length' <<< "${json}")"
  assert_eq "deploy-only compose omits build and publish" "0" "$(jq '[.actions[] | select(.job == "runtime" and (.stage == "build" or .stage == "publish"))] | length' <<< "${json}")"
  assert_eq "deploy-only compose keeps deploy" "1" "$(jq '[.actions[] | select(.job == "runtime" and .stage == "deploy" and .selected)] | length' <<< "${json}")"
  assert_eq "ship expands tag placeholder for git ref" "release-test123" "$(jq -r '.actions[] | select(.operation == "git.checkout") | .inputs.ref' <<< "${json}")"

  json="$(ops_run "${root}" ship production --job=application --no-push --no-deploy --json)"
  assert_eq "ship job filter selects one job" "application" "$(jq -r '.jobs[0].id' <<< "${json}")"
  assert_eq "ship no-push skips publish" "false" "$(jq -r '.actions[] | select(.stage == "publish") | .selected' <<< "${json}")"
  assert_eq "ship no-deploy skips deploy" "false" "$(jq -r '.actions[] | select(.stage == "deploy") | .selected' <<< "${json}")"

  json="$(ops_run "${root}" ship production --only=transfer --json)"
  assert_eq "ship only transfer selects transfer actions" "3" "$(jq '[.actions[] | select(.selected)] | length' <<< "${json}")"
  assert_eq "ship only transfer skips all other stages" "0" "$(jq '[.actions[] | select(.selected and .stage != "transfer")] | length' <<< "${json}")"

  output="$(ops_run "${root}" ship production --job=homepage --dry-run)"
  case "${output}" in
    *"Pipeline: production"*"files.sync"*"Dry-run only"*) assert_eq "ship human dry-run explains selected job" "true" "true" ;;
    *) assert_eq "ship human dry-run explains selected job" "true" "false" ;;
  esac

  assert_fail "ship execution remains safely blocked" 2 \
    ops_run "${root}" ship production

  assert_fail "ship rejects unknown jobs" 2 \
    ops_run "${root}" ship production --job=missing --dry-run
}
