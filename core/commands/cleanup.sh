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
CLEAN_PIDS=false
CLEAN_LOGS=false
LOG_DAYS=""

_usage_cleanup() {
  cat <<'EOF'
Usage: ops cleanup [--pids] [--logs-older-than=N] [--apply]

Preview or remove generated runtime state under .ops.project.

Defaults to --pids in preview mode.

Examples:
  ops cleanup
  ops cleanup --pids --apply
  ops cleanup --logs-older-than=30
  ops cleanup --logs-older-than=30 --apply
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    help|--help|-h)
      _usage_cleanup
      exit 0
      ;;
    --apply)
      APPLY=true
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
    --*)
      die "Unknown flag: $1. Use --help." 2
      ;;
    *)
      die "Unexpected argument: $1. Use --help." 2
      ;;
  esac
  shift
done

if [[ "${CLEAN_PIDS}" != "true" && "${CLEAN_LOGS}" != "true" ]]; then
  CLEAN_PIDS=true
fi

ops_section "ops cleanup"
if [[ "${APPLY}" == "true" ]]; then
  ops_warn "Applying cleanup changes under .ops.project"
else
  ops_info "Preview only. Use --apply to remove files."
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
