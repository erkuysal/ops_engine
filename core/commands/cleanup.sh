#!/usr/bin/env bash
# .ops/core/commands/cleanup.sh — Preview or remove stale runtime state.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/setup.sh"
source "${_SELF_DIR}/../lib/cleanup.sh"

APPLY=false
DRY_RUN=false
CATEGORY="runtime"
CLEAN_PIDS=false
CLEAN_LOGS=false
LOG_DAYS=""
IMAGE_REPOSITORY=""
MIN_VERSION=""
VERSION_RULE="semver"
VERSION_RULE_SET=false

_usage_cleanup() {
  cat <<'EOF'
Usage:
  ops cleanup [runtime] [--pids] [--logs-older-than=N] [--apply]
  ops cleanup images --repository=NAME --min-version=X.Y.Z [--version-rule=RULE] [--apply]
  ops cleanup generated [--apply]

Preview or remove explicitly selected cleanup categories.

Categories:
  runtime     Stale PID files and opt-in aged logs. This is the default.
  images      Local Docker image tags below a minimum version.
  generated   Rebuildable files under .ops.project/generated only.

All categories preview by default. Nothing is removed without --apply.

Image version rules:
  semver              Compare major, minor, and patch numerically (default).
  patch-first-digit   Legacy cleaner.sh behavior; 1.1.71 compares as 1.1.7.

Examples:
  ops cleanup
  ops cleanup --pids --apply
  ops cleanup --logs-older-than=30
  ops cleanup --logs-older-than=30 --apply
  ops cleanup images --repository=example/app --min-version=1.2.3
  ops cleanup images --repository=example/app --min-version=1.2.3 --apply
  ops cleanup generated
  ops cleanup generated --apply
EOF
}

case "${1:-}" in
  runtime|images|generated)
    CATEGORY="$1"
    shift
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    help|--help|-h)
      _usage_cleanup
      exit 0
      ;;
    --apply)
      [[ "${DRY_RUN}" != "true" ]] || die "--apply cannot be combined with --dry-run" 2
      APPLY=true
      ;;
    --dry-run|-n)
      [[ "${APPLY}" != "true" ]] || die "--dry-run cannot be combined with --apply" 2
      DRY_RUN=true
      ;;
    --pids)
      CLEAN_PIDS=true
      ;;
    --logs)
      CLEAN_LOGS=true
      ;;
    --logs-older-than=*)
      CLEAN_LOGS=true
      LOG_DAYS="${1#*=}"
      ;;
    --logs-older-than)
      die "--logs-older-than requires --logs-older-than=N form" 2
      ;;
    --repository=*)
      IMAGE_REPOSITORY="${1#*=}"
      ;;
    --repository)
      shift
      [[ $# -gt 0 ]] || die "--repository requires a value" 2
      IMAGE_REPOSITORY="$1"
      ;;
    --min-version=*)
      MIN_VERSION="${1#*=}"
      ;;
    --min-version)
      shift
      [[ $# -gt 0 ]] || die "--min-version requires a value" 2
      MIN_VERSION="$1"
      ;;
    --version-rule=*)
      VERSION_RULE="${1#*=}"
      VERSION_RULE_SET=true
      ;;
    --version-rule)
      shift
      [[ $# -gt 0 ]] || die "--version-rule requires a value" 2
      VERSION_RULE="$1"
      VERSION_RULE_SET=true
      ;;
    --*)
      die "Unknown flag: $1. Use --help." 2
      ;;
    *)
      die "Unexpected argument: $1. Use --help." 2
      ;;
  esac
  shift
done

ops_section "ops cleanup"
if [[ "${APPLY}" == "true" ]]; then
  ops_warn "Applying cleanup category: ${CATEGORY}"
else
  ops_info "Preview only. Use --apply to remove files."
fi

case "${CATEGORY}" in
  runtime)
    [[ -z "${IMAGE_REPOSITORY}" && -z "${MIN_VERSION}" && "${VERSION_RULE_SET}" != "true" ]] || \
      die "Image flags require the 'images' category" 2
    if [[ "${CLEAN_PIDS}" != "true" && "${CLEAN_LOGS}" != "true" ]]; then
      CLEAN_PIDS=true
    fi
    if [[ "${CLEAN_PIDS}" == "true" ]]; then
      printf '\nPID files\n'
      cleanup_stale_pid_files "${APPLY}"
    fi
    if [[ "${CLEAN_LOGS}" == "true" ]]; then
      [[ -n "${LOG_DAYS}" ]] || die "--logs requires --logs-older-than=N" 2
      printf '\nLog files older than %s days\n' "${LOG_DAYS}"
      cleanup_old_log_files "${APPLY}" "${LOG_DAYS}"
    fi
    ;;
  images)
    [[ "${CLEAN_PIDS}" != "true" && "${CLEAN_LOGS}" != "true" ]] || \
      die "Runtime flags cannot be combined with the 'images' category" 2
    printf '\nLocal Docker image tags\n'
    cleanup_local_images "${APPLY}" "${IMAGE_REPOSITORY}" "${MIN_VERSION}" "${VERSION_RULE}"
    ;;
  generated)
    [[ "${CLEAN_PIDS}" != "true" && "${CLEAN_LOGS}" != "true" ]] || \
      die "Runtime flags cannot be combined with the 'generated' category" 2
    [[ -z "${IMAGE_REPOSITORY}" && -z "${MIN_VERSION}" && "${VERSION_RULE_SET}" != "true" ]] || \
      die "Image flags cannot be combined with the 'generated' category" 2
    printf '\nGenerated project state\n'
    cleanup_generated_files "${APPLY}"
    ;;
esac
