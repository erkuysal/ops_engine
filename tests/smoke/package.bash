#!/usr/bin/env bash
# Package command smoke tests.

suite_package() {
  local root json
  root="$(fixture_copy config-only)"

  assert_ok "package status exits 0" \
    ops_run "${root}" package status

  json="$(OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" package status --json)"
  assert_eq "package status json has package root" "true" "$(jq -r '(.package_root | length) > 0' <<< "${json}")"
}
