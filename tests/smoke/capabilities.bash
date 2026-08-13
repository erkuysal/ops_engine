#!/usr/bin/env bash
# Capability manifest smoke tests: keep core/capabilities.json honest about
# what main.sh actually dispatches, and check the describe command surfaces it.

suite_capabilities() {
  local root main_ids manifest_ids missing extra out

  assert_file_exists "capabilities manifest exists" \
    "${OPS_CORE_ROOT}/capabilities.json"

  # Command/alias words main.sh's case statement actually dispatches, minus
  # the --flag style synonyms for help/version (those aren't command ids).
  main_ids="$(
    grep -oE '^  [a-zA-Z_|-]+\)' "${OPS_CORE_ROOT}/main.sh" \
      | sed -e 's/)$//' -e 's/^  *//' -e 's/|/\n/g' \
      | grep -vE '^-' \
      | sort -u
  )"

  manifest_ids="$(
    jq -r '.commands[] | [.id] + (.aliases // []) | .[]' "${OPS_CORE_ROOT}/capabilities.json" \
      | sort -u
  )"

  missing="$(comm -23 <(printf '%s\n' "${main_ids}") <(printf '%s\n' "${manifest_ids}"))"
  assert_eq "every main.sh command/alias has a capabilities.json entry" "" "${missing}"

  extra="$(comm -13 <(printf '%s\n' "${main_ids}") <(printf '%s\n' "${manifest_ids}"))"
  assert_eq "capabilities.json has no entries main.sh does not dispatch" "" "${extra}"

  # Every entry's script/doc path, when set, should exist on disk.
  HARNESS_TESTS_RUN=$((HARNESS_TESTS_RUN + 1))
  if bash -c '
    set -euo pipefail
    root="$1"
    jq -r ".commands[] | [.script, .doc] | .[] | select(. != null)" "${OPS_CORE_ROOT}/capabilities.json" |
      while IFS= read -r rel; do
        [[ -f "${root}/${rel}" ]] || { printf "missing: %s\n" "${rel}" >&2; exit 1; }
      done
  ' _ "${OPS_REPO_ROOT}"; then
    _harness_pass "capabilities.json script/doc paths resolve"
  else
    _harness_fail "capabilities.json script/doc paths resolve"
  fi

  root="$(fixture_copy config-only)"
  out="$(ops_run "${root}" describe --json)"
  assert_eq "describe --json conforms to the command-result envelope" "true" \
    "$(printf '%s' "${out}" | jq -e '.ok == true and .command == "describe" and (.commands | type) == "array"' >/dev/null 2>&1 && echo true || echo false)"

  HARNESS_TESTS_RUN=$((HARNESS_TESTS_RUN + 1))
  if printf '%s' "${out}" | jq -e '.commands[] | select(.id == "ship") | .safety == "plan_only"' >/dev/null; then
    _harness_pass "describe --json reports ship as plan_only"
  else
    _harness_fail "describe --json reports ship as plan_only"
  fi

  assert_ok "describe <command> resolves a known id" \
    ops_run "${root}" describe doctor

  assert_fail "describe <command> rejects an unknown id" 2 \
    ops_run "${root}" describe not-a-real-command
}
