#!/usr/bin/env bash
# Machine-global deployment profiles and project reference resolution.

suite_global_profiles() {
  local root fresh_root deferred_root selected_root created_root created_home global_home json
  root="$(fixture_copy container-pipeline)"
  global_home="$(mktemp -d "${TMPDIR:-/tmp}/ops-global-profiles-XXXXXX")"
  HARNESS_FIXTURES+=("${global_home}")

  OPS_GLOBAL_CONFIG_HOME="${global_home}" assert_ok "global profile setup apply" \
    ops_run "${root}" global setup personal-vps \
      --host=vps.example.test --user=deploy --path-template='/srv/{project}' \
      --ssh-key=/keys/deploy --docker-registry=registry.example.test \
      --docker-namespace=acme --docker-user=registry-user --apply

  assert_file_exists "global profile file written" "${global_home}/profiles/personal-vps.json"
  assert_eq "global profile file is private" "600" "$(stat -c '%a' "${global_home}/profiles/personal-vps.json")"

  json="$(OPS_GLOBAL_CONFIG_HOME="${global_home}" ops_run "${root}" global list --json)"
  assert_eq "global profile listed" "personal-vps" "$(jq -r '.[0]' <<< "${json}")"

  OPS_GLOBAL_CONFIG_HOME="${global_home}" assert_ok "project selects global profile" \
    ops_run "${root}" global use personal-vps --project-path=/srv/custom-app --apply
  assert_jq_eq "project stores only global profile reference" '.global_profile' \
    "${root}/.ops.project/config/ci.json" "personal-vps"
  assert_jq_eq "project inherited host remains absent" '.deploy.host' \
    "${root}/.ops.project/config/ci.json" ""

  json="$(OPS_GLOBAL_CONFIG_HOME="${global_home}" ops_run "${root}" global current --json)"
  assert_eq "current profile resolves deploy host" "vps.example.test" "$(jq -r '.deploy.host' <<< "${json}")"
  assert_eq "current profile resolves Docker login user" "registry-user" "$(jq -r '.docker.username' <<< "${json}")"
  assert_eq "project deploy path overrides template" "/srv/custom-app" "$(jq -r '.deploy.path' <<< "${json}")"

  json="$(OPS_GLOBAL_CONFIG_HOME="${global_home}" ops_run "${root}" deploy --service=infra --tag=test123 --json)"
  assert_eq "deploy resolves global SSH target" "deploy@vps.example.test" "$(jq -r '.remote' <<< "${json}")"
  assert_eq "deploy resolves project path override" "/srv/custom-app" "$(jq -r '.deploy_path' <<< "${json}")"

  json="$(OPS_GLOBAL_CONFIG_HOME="${global_home}" ops_run "${root}" build --service=api --tag=test123 --json)"
  assert_eq "build resolves global Docker registry and namespace" \
    "registry.example.test/acme/sample-api:test123" "$(jq -r '.targets[0].image' <<< "${json}")"

  OPS_GLOBAL_CONFIG_HOME="${global_home}" assert_ok "global profile update applies to referencing project" \
    ops_run "${root}" global setup personal-vps --host=new-vps.example.test --apply
  json="$(OPS_GLOBAL_CONFIG_HOME="${global_home}" ops_run "${root}" global current --json)"
  assert_eq "project sees updated global host without config rewrite" \
    "new-vps.example.test" "$(jq -r '.deploy.host' <<< "${json}")"

  fresh_root="$(fixture_copy config-only)"
  OPS_GLOBAL_CONFIG_HOME="${global_home}" assert_ok "ci setup accepts first profile selection" \
    ops_run "${fresh_root}" ci setup --global-profile=personal-vps --apply
  assert_jq_eq "ci setup persists selected profile" '.global_profile' \
    "${fresh_root}/.ops.project/config/ci.json" "personal-vps"
  json="$(OPS_GLOBAL_CONFIG_HOME="${global_home}" ops_run "${fresh_root}" ci show)"
  case "${json}" in
    *"Global profile: personal-vps"*"Deploy host: new-vps.example.test"*"Deploy path: /srv/fixture-config-only"*)
      assert_eq "ci show displays resolved global values" "true" "true" ;;
    *) assert_eq "ci show displays resolved global values" "true" "false" ;;
  esac

  deferred_root="$(fixture_copy config-only)"
  OPS_GLOBAL_CONFIG_HOME="${global_home}" assert_ok "ci setup can explicitly defer connection" \
    ops_run "${deferred_root}" ci setup --defer-connection --apply
  assert_jq_eq "deferred setup records first-use state" '.connection_deferred' \
    "${deferred_root}/.ops.project/config/ci.json" "true"
  assert_fail "non-interactive deploy rejects deferred connection" 2 \
    env OPS_GLOBAL_CONFIG_HOME="${global_home}" \
      OPS_PROJECT_ROOT="${deferred_root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" \
      OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
      bash "${OPS_CORE_ROOT}/main.sh" deploy --non-interactive --json

  selected_root="$(fixture_copy config-only)"
  if printf '1\n\n\n\n\n\n\n\n\n' |
      OPS_GLOBAL_CONFIG_HOME="${global_home}" \
      OPS_PROJECT_ROOT="${selected_root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" \
      OPS_PLAIN=true CI=false OPS_NON_INTERACTIVE=false \
      bash "${OPS_CORE_ROOT}/main.sh" ci setup --interactive --apply; then
    assert_eq "interactive setup selects a saved connection" "true" "true"
  else
    assert_eq "interactive setup selects a saved connection" "true" "false"
  fi
  assert_jq_eq "interactive selector persists profile reference" '.global_profile' \
    "${selected_root}/.ops.project/config/ci.json" "personal-vps"

  created_root="$(fixture_copy config-only)"
  created_home="$(mktemp -d "${TMPDIR:-/tmp}/ops-created-profile-XXXXXX")"
  HARNESS_FIXTURES+=("${created_home}")
  if printf '1\nnew-vps\nvps.example.test\ndeploy\n/srv/{project}\n/keys/new-vps\nghcr.io\nacme\nacme\n\n\n\n\n\n\n\n\n\nn\nn\n' |
      OPS_GLOBAL_CONFIG_HOME="${created_home}" \
      OPS_PROJECT_ROOT="${created_root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" \
      OPS_PLAIN=true CI=false OPS_NON_INTERACTIVE=false \
      bash "${OPS_CORE_ROOT}/main.sh" ci setup --interactive --apply; then
    assert_eq "interactive setup creates a reusable connection" "true" "true"
  else
    assert_eq "interactive setup creates a reusable connection" "true" "false"
  fi
  assert_file_exists "interactive setup writes created global profile" \
    "${created_home}/profiles/new-vps.json"
  assert_jq_eq "interactive setup links newly created profile" '.global_profile' \
    "${created_root}/.ops.project/config/ci.json" "new-vps"
}
