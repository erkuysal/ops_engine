#!/usr/bin/env bash
# Healthcheck library and start integration smoke tests.

suite_healthcheck() {
  local root url pid services_file

  root="$(fixture_copy env-service)"
  ops_run "${root}" setup --apply >/dev/null 2>&1

  OPS_PROJECT_ROOT="${root}"
  OPS_CORE_ROOT="${OPS_CORE_ROOT}"
  export OPS_PROJECT_ROOT OPS_CORE_ROOT
  ops_source_lib healthcheck.sh

  url="$(healthcheck_service_url backend)"
  assert_eq "inferred health url from port" "http://localhost:8000/" "${url}"

  services_file="${root}/.ops.project/config/services.json"
  jq '.services[0].healthcheck = "http://localhost:9999/health"' \
    "${services_file}" > "${services_file}.tmp"
  mv "${services_file}.tmp" "${services_file}"
  url="$(healthcheck_service_url backend)"
  assert_eq "explicit healthcheck wins" "http://localhost:9999/health" "${url}"

  if command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    python3 -m http.server 18765 --bind 127.0.0.1 >/dev/null 2>&1 &
    pid=$!
    sleep 1
    assert_ok "healthcheck_wait_url succeeds" \
      healthcheck_wait_url "http://127.0.0.1:18765/" 5 1
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true

    assert_fail "healthcheck_wait_url times out" 1 \
      healthcheck_wait_url "http://127.0.0.1:1/" 2 1
  fi

  root="$(fixture_copy config-only)"
  assert_ok "start --dry-run --no-wait" \
    ops_run "${root}" start api --dry-run --no-wait
}
