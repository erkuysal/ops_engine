#!/usr/bin/env bash
# .ops/core/lib/boundaries.sh — Package/project boundary checks.

set -euo pipefail
if [[ "${_OPS_CORE_BOUNDARIES_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_BOUNDARIES_LOADED=1

ops_package_root() {
  if [[ -n "${OPS_PACKAGE_ROOT:-}" ]]; then
    printf '%s' "${OPS_PACKAGE_ROOT}"
    return 0
  fi
  dirname "${OPS_CORE_ROOT}"
}

_boundary_relpath() {
  local path="$1" root="$2"
  printf '%s' "${path#${root}/}"
}

boundary_scan_text() {
  local root="$1" pattern="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -n --hidden --glob '!.git/**' --glob '!log' --glob '!tests/fixtures/**' --glob '!**/core/lib/boundaries.sh' "${pattern}" "${root}" || true
  else
    grep -RIn --exclude=boundaries.sh --exclude=log --exclude-dir=.git --exclude-dir=fixtures -E "${pattern}" "${root}" 2>/dev/null || true
  fi
}

boundary_find_files() {
  local root="$1"
  shift
  find "${root}" "$@" 2>/dev/null || true
}

boundary_doctor() {
  local root
  root="$(ops_package_root)"

  local pass=0 fail=0
  local findings=()

  _boundary_pass() {
    pass=$((pass + 1))
    printf 'ok    %s\n' "$*"
  }

  _boundary_fail() {
    fail=$((fail + 1))
    findings+=("$*")
    printf 'FAIL  %s\n' "$*" >&2
  }

  printf 'ops boundary doctor\n'
  printf 'package: %s\n\n' "${root}"

  if [[ -d "${root}/core" && -d "${root}/docs" ]]; then
    _boundary_pass "package root looks like .ops"
  else
    _boundary_fail "package root is missing expected core/docs directories"
  fi

  local dir
  for dir in bin generated setup .tmp .history .ops.project; do
    if [[ -e "${root}/${dir}" ]]; then
      _boundary_fail "package contains mutable/generated directory: ${dir}"
    else
      _boundary_pass "no package-local ${dir}/ directory"
    fi
  done

  local secret_files
  secret_files="$(boundary_find_files "${root}" \
    -path "${root}/.git" -prune -o \
    -path "${root}/tests/fixtures" -prune -o \
    -type f \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name 'id_rsa' -o -name 'id_ed25519' \) -print)"
  if [[ -n "${secret_files}" ]]; then
    while IFS= read -r path; do
      [[ -n "${path}" ]] && _boundary_fail "package contains secret-like file: $(_boundary_relpath "${path}" "${root}")"
    done <<< "${secret_files}"
  else
    _boundary_pass "no secret-like files under package"
  fi

  local machine_paths
  machine_paths="$(boundary_scan_text "${root}" '(C:\\Users\\|C:\\Program Files\\|D:/DEV/UNDER_DEVELOPMENT/personal|/mnt/d/DEV/UNDER_DEVELOPMENT/personal)')"
  if [[ -n "${machine_paths}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] && _boundary_fail "machine-local path reference: ${line#${root}/}"
    done <<< "${machine_paths}"
  else
    _boundary_pass "no machine-local path references"
  fi

  local project_terms
  project_terms="$(boundary_scan_text "${root}" '\b(userengine|voice_app|soundilerry|api_core|personal-site|BACKENDs)\b')"
  if [[ -n "${project_terms}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] && _boundary_fail "project-specific package reference: ${line#${root}/}"
    done <<< "${project_terms}"
  else
    _boundary_pass "no project-specific package references"
  fi

  printf '\nBoundary summary: %d passed, %d failed\n' "${pass}" "${fail}"

  if (( fail > 0 )); then
    return 1
  fi
  return 0
}

return 0
