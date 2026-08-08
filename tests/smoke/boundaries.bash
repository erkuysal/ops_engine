#!/usr/bin/env bash
# Package boundary smoke tests.

suite_boundaries() {
  local root
  root="$(fixture_copy config-only)"

  assert_ok "boundary doctor exits 0" \
    ops_run "${root}" doctor boundaries

  assert_fail "runtime boundary avoids legacy manifest accessors" 1 \
    grep -En 'require_manifest_or_config|manifest_(list_services|service_exists|get_project_field|get_service_field|get_service_list_field)|_manifest_yq' \
      "${OPS_CORE_ROOT}"/commands/{build,deploy,env,logs,monitor,run,show,start,status,stop}.sh \
      "${OPS_CORE_ROOT}"/lib/{container_pipeline,env,env_materialize,graph,run_plan,runner,status}.sh \
      "${OPS_CORE_ROOT}"/stacks/{docker,go}.sh
}
