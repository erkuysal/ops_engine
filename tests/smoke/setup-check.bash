#!/usr/bin/env bash
# Setup check (drift detection) smoke tests.

suite_setup_check() {
  local root services_file output

  root="$(fixture_copy env-service)"
  assert_ok "setup --apply for check baseline" \
    ops_run "${root}" setup --apply

  assert_ok "check passes when config matches discovery" \
    ops_run "${root}" setup check

  services_file="${root}/.ops.project/config/services.json"
  jq '(.services[] | select(.id == "backend") | .path) = "backend-moved"' \
    "${services_file}" > "${services_file}.tmp"
  mv "${services_file}.tmp" "${services_file}"

  assert_fail "check fails when service path drifts" 1 \
    ops_run "${root}" setup check

  set +e
  output="$(OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" setup check --json 2>&1)"
  set -e
  assert_eq "json reports path drift" "1" "$(jq -r '.summary.changed' <<< "${output}")"
  assert_eq "json names drifted field" "path" "$(jq -r '.changed[0].fields[0].name' <<< "${output}")"

  root="$(fixture_copy env-service)"
  assert_fail "check fails before config exists" 1 \
    ops_run "${root}" setup check
}
