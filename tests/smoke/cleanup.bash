#!/usr/bin/env bash
# Cleanup command smoke tests.

suite_cleanup() {
  local root generated_file history_file profile_file secret_file output candidate_count
  local fake_bin fake_log outside symlink_root

  root="$(fixture_copy config-only)"
  mkdir -p "${root}/.ops.project/run"
  printf '%s' "99999999" > "${root}/.ops.project/run/api.pid"

  assert_ok "cleanup previews stale pid" \
    ops_run "${root}" cleanup --pids
  assert_file_exists "cleanup preview keeps stale pid" \
    "${root}/.ops.project/run/api.pid"

  assert_ok "cleanup removes stale pid" \
    ops_run "${root}" cleanup --pids --apply
  if [[ -f "${root}/.ops.project/run/api.pid" ]]; then
    _harness_fail "cleanup apply removes stale pid" "pid file still exists"
  else
    _harness_pass "cleanup apply removes stale pid"
  fi

  fake_bin="${OPS_TESTS_DIR}/fixtures/bin"
  fake_log="${root}/docker-removals.log"

  output="$(
    PATH="${fake_bin}:${PATH}" FAKE_DOCKER_LOG="${fake_log}" \
      ops_run "${root}" cleanup images \
        --repository=example/app --min-version=1.1.8
  )"
  candidate_count="$(grep -c '^image candidate:' <<< "${output}")"
  assert_eq "image cleanup uses normal semver by default" "1" "${candidate_count}"
  if [[ -f "${fake_log}" ]]; then
    _harness_fail "image cleanup preview keeps tags" "fake Docker recorded a removal"
  else
    _harness_pass "image cleanup preview keeps tags"
  fi

  output="$(
    PATH="${fake_bin}:${PATH}" FAKE_DOCKER_LOG="${fake_log}" \
      ops_run "${root}" cleanup images \
        --repository=example/app --min-version=1.1.8 \
        --version-rule=patch-first-digit
  )"
  candidate_count="$(grep -c '^image candidate:' <<< "${output}")"
  assert_eq "legacy image rule preserves first-patch-digit behavior" "2" "${candidate_count}"

  if PATH="${fake_bin}:${PATH}" FAKE_DOCKER_LOG="${fake_log}" \
    ops_run "${root}" cleanup images \
      --repository=example/app --min-version=1.1.8 --apply; then
    _harness_pass "image cleanup apply removes exact tag reference"
  else
    _harness_fail "image cleanup apply removes exact tag reference"
  fi
  assert_eq "image cleanup does not remove by shared image id" \
    "example/app:v1.1.7" "$(cat "${fake_log}")"
  assert_fail "image cleanup requires explicit repository and version" 2 \
    ops_run "${root}" cleanup images
  assert_fail "cleanup rejects conflicting preview and apply flags" 2 \
    ops_run "${root}" cleanup generated --dry-run --apply
  assert_fail "generated cleanup rejects runtime flags" 2 \
    ops_run "${root}" cleanup generated --pids

  generated_file="${root}/.ops.project/generated/run-plans/api.start.json"
  history_file="${root}/.ops.project/.history/config/keep.json"
  profile_file="${root}/.ops.project/profiles/local.json"
  secret_file="${root}/.ops.project/secrets/ci.env"
  mkdir -p \
    "$(dirname "${generated_file}")" \
    "$(dirname "${history_file}")" \
    "$(dirname "${profile_file}")" \
    "$(dirname "${secret_file}")"
  printf '{}' > "${generated_file}"
  printf '{}' > "${history_file}"
  printf '{}' > "${profile_file}"
  printf 'SECRET=keep' > "${secret_file}"

  assert_ok "generated cleanup preview exits 0" \
    ops_run "${root}" cleanup generated
  assert_file_exists "generated cleanup preview keeps generated files" "${generated_file}"

  assert_ok "generated cleanup apply exits 0" \
    ops_run "${root}" cleanup generated --apply
  if [[ -f "${generated_file}" ]]; then
    _harness_fail "generated cleanup removes generated files" "generated file still exists"
  else
    _harness_pass "generated cleanup removes generated files"
  fi
  assert_file_exists "generated cleanup preserves config" \
    "${root}/.ops.project/config/project.json"
  assert_file_exists "generated cleanup preserves history" "${history_file}"
  assert_file_exists "generated cleanup preserves profiles" "${profile_file}"
  assert_file_exists "generated cleanup preserves secrets" "${secret_file}"

  symlink_root="$(fixture_copy config-only)"
  outside="$(mktemp -d "${TMPDIR:-/tmp}/ops-cleanup-outside-XXXXXX")"
  HARNESS_FIXTURES+=("${outside}")
  printf 'keep' > "${outside}/keep.txt"
  rm -rf "${symlink_root}/.ops.project/generated"
  ln -s "${outside}" "${symlink_root}/.ops.project/generated"
  assert_fail "generated cleanup rejects symlink targets" 1 \
    ops_run "${symlink_root}" cleanup generated --apply
  assert_file_exists "generated cleanup leaves symlink target untouched" \
    "${outside}/keep.txt"
}
