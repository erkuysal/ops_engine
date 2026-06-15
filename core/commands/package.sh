#!/usr/bin/env bash
# .ops/core/commands/package.sh — Inspect the ops package checkout/install state.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"

SUBCMD="${1:-status}"
[[ $# -gt 0 ]] && shift || true
JSON=false

_usage_package() {
  cat <<'EOF'
Usage: ops package status [--json]

Inspect the .ops package checkout, Git state, and installed package metadata.
EOF
}

for arg in "$@"; do
  case "${arg}" in
    --json) JSON=true ;;
    help|--help|-h) _usage_package; exit 0 ;;
    *) die "Unknown package flag: ${arg}" 2 ;;
  esac
done

case "${SUBCMD}" in
  status|help|--help|-h) ;;
  *) die "Unknown package subcommand: ${SUBCMD}" 2 ;;
esac

if [[ "${SUBCMD}" == "help" || "${SUBCMD}" == "--help" || "${SUBCMD}" == "-h" ]]; then
  _usage_package
  exit 0
fi

PACKAGE_ROOT="$(dirname "${OPS_CORE_ROOT}")"
PACKAGE_MARKER="${PACKAGE_ROOT}/../.ops-install-source"

_core_version() {
  sed -n 's/^OPS_CORE_VERSION="\([^"]*\)".*/\1/p' "${OPS_CORE_ROOT}/main.sh" 2>/dev/null | sed -n '1p'
}

_marker_get() {
  local key="$1"
  [[ -f "${PACKAGE_MARKER}" ]] || return 0
  sed -n "s/^${key}=//p" "${PACKAGE_MARKER}" 2>/dev/null | sed -n '1p'
}

_git_direct() {
  command -v git >/dev/null 2>&1 || return 1
  git -C "${PACKAGE_ROOT}" "$@" 2>/dev/null
}

_wsl_path() {
  local path="$1"
  if command -v wslpath >/dev/null 2>&1; then
    wslpath -a -u "${path}" 2>/dev/null | tr -d '\r'
    return 0
  fi
  case "${path}" in
    [A-Za-z]:\\*)
      local drive rest
      drive="$(printf '%s' "${path:0:1}" | tr '[:upper:]' '[:lower:]')"
      rest="${path:2}"
      rest="${rest//\\//}"
      printf '/mnt/%s%s' "${drive}" "${rest}"
      return 0
      ;;
    [A-Za-z]:/*)
      local drive rest
      drive="$(printf '%s' "${path:0:1}" | tr '[:upper:]' '[:lower:]')"
      rest="${path:2}"
      printf '/mnt/%s%s' "${drive}" "${rest}"
      return 0
      ;;
  esac
  return 1
}

_git_wsl() {
  command -v wsl.exe >/dev/null 2>&1 || command -v bash >/dev/null 2>&1 || return 1
  local wsl_root
  wsl_root="$(_wsl_path "${PACKAGE_ROOT}")" || return 1
  if command -v wsl.exe >/dev/null 2>&1; then
    wsl.exe --cd "${wsl_root}" git "$@" 2>/dev/null | tr -d '\r'
  else
    bash -lc "cd $(printf '%q' "${wsl_root}") && git $(printf '%q ' "$@")" 2>/dev/null | tr -d '\r'
  fi
}

_git_cmd() {
  _git_direct "$@" || _git_wsl "$@" || return 1
}

GIT_AVAILABLE=false
GIT_VIA="none"
if _git_direct rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_AVAILABLE=true
  GIT_VIA="git"
elif _git_wsl rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_AVAILABLE=true
  GIT_VIA="wsl-git"
fi

IS_GIT_REPO=false
BRANCH=""
REVISION=""
COMMIT_DATE=""
DIRTY_COUNT=0
UNTRACKED_COUNT=0

if [[ "${GIT_AVAILABLE}" == "true" ]]; then
  IS_GIT_REPO="$(_git_cmd rev-parse --is-inside-work-tree 2>/dev/null || printf false)"
  BRANCH="$(_git_cmd branch --show-current 2>/dev/null || true)"
  REVISION="$(_git_cmd rev-parse --short HEAD 2>/dev/null || true)"
  COMMIT_DATE="$(_git_cmd log -1 --format=%cI 2>/dev/null || true)"
  DIRTY_COUNT="$(_git_cmd status --porcelain 2>/dev/null | grep -vc '^??' || true)"
  UNTRACKED_COUNT="$(_git_cmd status --porcelain 2>/dev/null | grep -c '^??' || true)"
fi

INSTALLED_MANAGED=false
if [[ -f "${PACKAGE_MARKER}" ]] && grep -q '^managed-by=ops-install$' "${PACKAGE_MARKER}" 2>/dev/null; then
  INSTALLED_MANAGED=true
fi

if [[ "${JSON}" == "true" ]]; then
  require_bins jq
  jq -n \
    --arg package_root "${PACKAGE_ROOT}" \
    --arg core_version "$(_core_version)" \
    --argjson git_available "${GIT_AVAILABLE}" \
    --arg git_via "${GIT_VIA}" \
    --argjson is_git_repo "${IS_GIT_REPO}" \
    --arg branch "${BRANCH}" \
    --arg revision "${REVISION}" \
    --arg commit_date "${COMMIT_DATE}" \
    --arg dirty_count "${DIRTY_COUNT}" \
    --arg untracked_count "${UNTRACKED_COUNT}" \
    --arg marker "${PACKAGE_MARKER}" \
    --argjson installed_managed "${INSTALLED_MANAGED}" \
    --arg installed_version "$(_marker_get ops-core-version)" \
    --arg installed_revision "$(_marker_get source-revision)" \
    --arg installed_at "$(_marker_get installed-at)" \
    --arg updated_at "$(_marker_get updated-at)" \
    '{
      package_root: $package_root,
      core_version: $core_version,
      git: {
        available: $git_available,
        via: $git_via,
        is_repo: $is_git_repo,
        branch: $branch,
        revision: $revision,
        commit_date: $commit_date,
        dirty_count: ($dirty_count | tonumber? // 0),
        untracked_count: ($untracked_count | tonumber? // 0)
      },
      installed_package: {
        marker: $marker,
        managed: $installed_managed,
        version: $installed_version,
        revision: $installed_revision,
        installed_at: $installed_at,
        updated_at: $updated_at
      }
    }'
  exit 0
fi

ops_section "ops package status"
printf '  package root: %s\n' "${PACKAGE_ROOT}"
printf '  core version: %s\n' "$(_core_version)"
printf '  git available: %s' "${GIT_AVAILABLE}"
[[ "${GIT_AVAILABLE}" == "true" ]] && printf ' (%s)' "${GIT_VIA}"
printf '\n'

if [[ "${GIT_AVAILABLE}" == "true" ]]; then
  printf '  git repo: %s\n' "${IS_GIT_REPO}"
  printf '  branch: %s\n' "${BRANCH:-unknown}"
  printf '  revision: %s\n' "${REVISION:-unknown}"
  printf '  commit date: %s\n' "${COMMIT_DATE:-unknown}"
  printf '  dirty files: %s\n' "${DIRTY_COUNT}"
  printf '  untracked files: %s\n' "${UNTRACKED_COUNT}"
else
  printf '  git note: git unavailable from this shell'
  if command -v wsl.exe >/dev/null 2>&1 || command -v bash >/dev/null 2>&1; then
    printf '; WSL Git was attempted but did not respond'
  fi
  printf '\n'
fi

printf '\nInstalled package\n'
if [[ -f "${PACKAGE_MARKER}" ]]; then
  printf '  marker: %s\n' "${PACKAGE_MARKER}"
  printf '  managed: %s\n' "${INSTALLED_MANAGED}"
  printf '  version: %s\n' "$(_marker_get ops-core-version)"
  printf '  revision: %s\n' "$(_marker_get source-revision)"
  printf '  installed: %s\n' "$(_marker_get installed-at)"
  printf '  updated: %s\n' "$(_marker_get updated-at)"
else
  printf '  marker: not found\n'
fi
