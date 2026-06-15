#!/usr/bin/env bash
# Monitor command smoke tests.

suite_monitor() {
  local root json tmp_json
  root="$(fixture_copy config-only)"

  assert_ok "monitor doctor exits 0" \
    ops_run "${root}" monitor doctor

  assert_ok "monitor status exits 0" \
    ops_run "${root}" monitor status

  json="$(OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" monitor status --json)"
  assert_eq "monitor status json has targets" "true" "$(jq -r 'has("targets")' <<< "${json}")"

  json="$(OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" monitor hosts --port=1 --json)"
  assert_eq "monitor hosts json has candidates" "true" "$(jq -r 'has("candidates")' <<< "${json}")"
  assert_eq "monitor hosts includes loopback" "true" "$(jq -r '[.candidates[].label] | index("loopback") != null' <<< "${json}")"

  assert_ok "monitor setup preview exits 0" \
    ops_run "${root}" monitor setup
  assert_ok "monitor setup apply exits 0" \
    ops_run "${root}" monitor setup --apply
  assert_file_exists "monitor setup writes config" \
    "${root}/.ops.project/config/monitoring.json"
  assert_jq_eq "monitor setup derives health and tcp targets" \
    '.targets | length' "${root}/.ops.project/config/monitoring.json" "2"
  assert_jq_eq "monitor setup derives service port" \
    '.targets[] | select(.id == "api.tcp") | .port' "${root}/.ops.project/config/monitoring.json" "8080"
  assert_ok "monitor setup applies service host override" \
    ops_run "${root}" monitor setup --service-host=api=host.docker.internal --apply
  assert_jq_eq "monitor setup stores service host override" \
    '.targets[] | select(.id == "api.tcp") | .host' "${root}/.ops.project/config/monitoring.json" "host.docker.internal"
  assert_fail "monitor setup rejects option-looking host override" 2 \
    ops_run "${root}" monitor setup --target-host=api.tcp=--apply

  assert_ok "monitor setup applies infra targets" \
    ops_run "${root}" monitor setup --postgres --redis --apply
  assert_file_exists "monitor setup writes infra env" \
    "${root}/.ops.project/secrets/infra.env"
  assert_eq "monitor setup writes postgres db default" "POSTGRES_DB=postgres" \
    "$(grep -E '^POSTGRES_DB=' "${root}/.ops.project/secrets/infra.env")"
  assert_eq "monitor setup writes postgres user default" "POSTGRES_USER=postgres" \
    "$(grep -E '^POSTGRES_USER=' "${root}/.ops.project/secrets/infra.env")"
  assert_eq "monitor setup writes redis db default" "REDIS_DB=0" \
    "$(grep -E '^REDIS_DB=' "${root}/.ops.project/secrets/infra.env")"
  assert_jq_eq "monitor setup includes infra targets" \
    '.targets | length' "${root}/.ops.project/config/monitoring.json" "4"
  assert_jq_eq "monitor setup stores postgres password env ref" \
    '.targets[] | select(.id == "postgres.local") | .password_env' "${root}/.ops.project/config/monitoring.json" "POSTGRES_PASSWORD"
  assert_jq_eq "monitor setup stores redis db env ref" \
    '.targets[] | select(.id == "redis.local") | .db_env' "${root}/.ops.project/config/monitoring.json" "REDIS_DB"
  json="$(OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" monitor postgres info --json)"
  assert_eq "monitor postgres info json has target" "postgres.local" "$(jq -r '.target.id' <<< "${json}")"
  assert_eq "monitor postgres info json redacts password" "false" "$(jq -r 'has("password")' <<< "${json}")"
  assert_eq "monitor postgres info reports password presence only" "true" "$(jq -r '.connection | has("password_present")' <<< "${json}")"

  assert_ok "monitor setup updates infra target env refs" \
    ops_run "${root}" monitor setup \
      --postgres-db=appdb \
      --postgres-user=appuser \
      --postgres-db-env=PGDATABASE \
      --postgres-user-env=PGUSER \
      --postgres-password-env=PGPASSWORD \
      --redis-db=2 \
      --redis-db-env=REDIS_DATABASE \
      --redis-password-env=REDIS_PASS \
      --apply
  assert_jq_eq "monitor setup stores custom postgres db env ref" \
    '.targets[] | select(.id == "postgres.local") | .db_env' "${root}/.ops.project/config/monitoring.json" "PGDATABASE"
  assert_jq_eq "monitor setup stores custom redis password env ref" \
    '.targets[] | select(.id == "redis.local") | .password_env' "${root}/.ops.project/config/monitoring.json" "REDIS_PASS"
  assert_eq "monitor setup upserts custom postgres db value" "PGDATABASE=appdb" \
    "$(grep -E '^PGDATABASE=' "${root}/.ops.project/secrets/infra.env")"
  assert_eq "monitor setup upserts custom redis db value" "REDIS_DATABASE=2" \
    "$(grep -E '^REDIS_DATABASE=' "${root}/.ops.project/secrets/infra.env")"

  assert_ok "monitor setup writes explicit local db passwords" \
    ops_run "${root}" monitor setup \
      --postgres-user=admin \
      --postgres-password=admin \
      --redis-password=admin \
      --apply
  assert_eq "monitor setup upserts postgres user default" "POSTGRES_USER=admin" \
    "$(grep -E '^POSTGRES_USER=' "${root}/.ops.project/secrets/infra.env")"
  assert_eq "monitor setup upserts postgres password value" "POSTGRES_PASSWORD=admin" \
    "$(grep -E '^POSTGRES_PASSWORD=' "${root}/.ops.project/secrets/infra.env")"
  assert_eq "monitor setup upserts redis password value" "REDIS_PASSWORD=admin" \
    "$(grep -E '^REDIS_PASSWORD=' "${root}/.ops.project/secrets/infra.env")"

  assert_ok "monitor credentials exits 0" \
    ops_run "${root}" monitor credentials
  json="$(OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" monitor credentials --json)"
  assert_eq "monitor credentials json has infra targets" "2" "$(jq -r '.targets | length' <<< "${json}")"

  json="$(OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" monitor status --json)"
  assert_eq "monitor status dedupes configured targets" "4" "$(jq -r '.targets | length' <<< "${json}")"

  assert_eq "monitor status json includes summary" "true" "$(jq -r '.summary | has("ok")' <<< "${json}")"

  tmp_json="$(mktemp)"
  jq '.targets += [{id: "unsupported.local", kind: "unsupported", source: "test"}]' \
    "${root}/.ops.project/config/monitoring.json" > "${tmp_json}"
  mv "${tmp_json}" "${root}/.ops.project/config/monitoring.json"
  assert_ok "monitor test ignores unknown by default" \
    ops_run "${root}" monitor test --target=unsupported.local
  assert_fail "monitor test strict fails unknown" 1 \
    ops_run "${root}" monitor test --target=unsupported.local --strict
}
