#!/usr/bin/env bash
# Shared test harness for the ops package.
# Source this file from tests/run.sh and smoke suites.

set -euo pipefail

if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  printf 'harness: bash 4+ required\n' >&2
  exit 2
fi

OPS_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPS_CORE_ROOT="${OPS_REPO_ROOT}/core"
OPS_TESTS_DIR="${OPS_REPO_ROOT}/tests"

HARNESS_TESTS_RUN=0
HARNESS_TESTS_FAILED=0
HARNESS_FIXTURES=()

require_bins() {
  local bin
  local missing=()
  for bin in "$@"; do
    command -v "${bin}" >/dev/null 2>&1 || missing+=("${bin}")
  done

  [[ ${#missing[@]} -eq 0 ]] && return 0

  printf 'harness: missing required tools: %s\n' "${missing[*]}" >&2
  for bin in "${missing[@]}"; do
    case "${bin}" in
      bash) printf '  bash: install Bash 4.3 or newer\n' >&2 ;;
      jq)   printf '  jq:   https://jqlang.github.io/jq/download/\n' >&2 ;;
      yq)   printf '  yq:   install mikefarah/yq v4\n' >&2 ;;
      *)    printf '  %s: install it and ensure it is on PATH\n' "${bin}" >&2 ;;
    esac
  done
  printf 'See docs/development.md for the complete test prerequisites.\n' >&2
  exit 2
}

require_bins bash jq yq

ops_run() {
  local project_root="$1"
  shift
  (
    # Drop cached project paths so each fixture root resolves its own .ops.project state.
    unset OPS_PROJECT_STATE_DIR OPS_PROJECT_LOG_DIR OPS_PROJECT_RUN_DIR OPS_PROJECT_GENERATED_DIR
    unset OPS_PROJECT_CONFIG_DIR OPS_PROJECT_CONFIG_SERVICES_FILE OPS_PROJECT_CONFIG_PROJECT_FILE
    unset OPS_PROJECT_CONFIG_SETTINGS_FILE OPS_PROJECT_CONFIG_PROFILES_FILE OPS_PROJECT_HISTORY_DIR
    unset OPS_PROJECT_SETUP_GENERATED_FILE OPS_PROJECT_SETUP_GENERATED_LEGACY_FILE OPS_PROFILES_DIR
    OPS_PROJECT_ROOT="${project_root}" \
    OPS_CORE_ROOT="${OPS_CORE_ROOT}" \
    OPS_PLAIN=true \
    CI=true \
    OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" "$@"
  )
}

ops_run_interactive() {
  local project_root="$1"
  shift
  (
    # Match ops_run isolation while leaving stdin attached to the caller's prompt input.
    unset OPS_PROJECT_STATE_DIR OPS_PROJECT_LOG_DIR OPS_PROJECT_RUN_DIR OPS_PROJECT_GENERATED_DIR
    unset OPS_PROJECT_CONFIG_DIR OPS_PROJECT_CONFIG_SERVICES_FILE OPS_PROJECT_CONFIG_PROJECT_FILE
    unset OPS_PROJECT_CONFIG_SETTINGS_FILE OPS_PROJECT_CONFIG_PROFILES_FILE OPS_PROJECT_HISTORY_DIR
    unset OPS_PROJECT_SETUP_GENERATED_FILE OPS_PROJECT_SETUP_GENERATED_LEGACY_FILE OPS_PROFILES_DIR
    OPS_PROJECT_ROOT="${project_root}" \
    OPS_CORE_ROOT="${OPS_CORE_ROOT}" \
    OPS_PLAIN=true \
    CI=false \
    OPS_NON_INTERACTIVE=false \
    bash "${OPS_CORE_ROOT}/main.sh" "$@"
  )
}

ops_source_lib() {
  local lib="$1"
  # shellcheck source=/dev/null
  source "${OPS_CORE_ROOT}/lib/init.sh"
  # shellcheck source=/dev/null
  source "${OPS_CORE_ROOT}/lib/${lib}"
}

fixture_path() {
  printf '%s/fixtures/%s' "${OPS_TESTS_DIR}" "$1"
}

fixture_copy() {
  local name="$1"
  local dest
  dest="$(mktemp -d "${TMPDIR:-/tmp}/ops-fixture-${name}-XXXXXX")"
  cp -a "$(fixture_path "${name}")/." "${dest}/"
  HARNESS_FIXTURES+=("${dest}")
  printf '%s' "${dest}"
}

fixture_cleanup_all() {
  local dir
  for dir in "${HARNESS_FIXTURES[@]+"${HARNESS_FIXTURES[@]}"}"; do
    [[ -n "${dir}" && -d "${dir}" ]] && rm -rf "${dir}"
  done
  HARNESS_FIXTURES=()
}

_harness_fail() {
  local name="$1" detail="${2:-}"
  HARNESS_TESTS_FAILED=$((HARNESS_TESTS_FAILED + 1))
  printf '  FAIL  %s' "${name}" >&2
  [[ -n "${detail}" ]] && printf ': %s' "${detail}" >&2
  printf '\n' >&2
}

_harness_pass() {
  local name="$1"
  HARNESS_TESTS_RUN=$((HARNESS_TESTS_RUN + 1))
  printf '  ok    %s\n' "${name}"
}

assert_ok() {
  local name="$1"
  shift
  if "$@"; then
    _harness_pass "${name}"
  else
    _harness_fail "${name}" "expected success"
  fi
}

assert_fail() {
  local name="$1"
  local expected_code="${2:-1}"
  shift 2
  set +e
  "$@"
  local code=$?
  set -e
  HARNESS_TESTS_RUN=$((HARNESS_TESTS_RUN + 1))
  if [[ "${code}" -eq "${expected_code}" ]]; then
    _harness_pass "${name}"
  else
    _harness_fail "${name}" "expected exit ${expected_code}, got ${code}"
  fi
}

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  HARNESS_TESTS_RUN=$((HARNESS_TESTS_RUN + 1))
  if [[ "${actual}" == "${expected}" ]]; then
    _harness_pass "${name}"
  else
    _harness_fail "${name}" "expected '${expected}', got '${actual}'"
  fi
}

assert_file_exists() {
  local name="$1"
  local path="$2"
  HARNESS_TESTS_RUN=$((HARNESS_TESTS_RUN + 1))
  if [[ -f "${path}" ]]; then
    _harness_pass "${name}"
  else
    _harness_fail "${name}" "missing file ${path}"
  fi
}

assert_jq_eq() {
  local name="$1"
  local jq_expr="$2"
  local file="$3"
  local expected="$4"
  local actual
  actual="$(jq -r "${jq_expr}" "${file}")"
  assert_eq "${name}" "${expected}" "${actual}"
}

harness_summary() {
  printf '\n---\n'
  printf 'tests: %d run, %d failed\n' "${HARNESS_TESTS_RUN}" "${HARNESS_TESTS_FAILED}"
  if [[ "${HARNESS_TESTS_FAILED}" -gt 0 ]]; then
    return 1
  fi
  return 0
}

trap fixture_cleanup_all EXIT
