#!/usr/bin/env bash
# .ops/core/commands/bootstrap.sh - Compatibility wrapper for setup.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/manifest.sh"

DRY_RUN=false
FORCE=false

for _arg in "$@"; do
  case "${_arg}" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
    --help|-h)
      cat <<'EOF'
Usage: ops bootstrap [--dry-run] [--force]

Compatibility wrapper for:
  ops setup --dry-run
  ops setup --apply
  ops setup apply-services --apply

`setup` is now the project initializer and discovery engine.
EOF
      exit 0
      ;;
    *) die "Unknown flag: ${_arg}. Use --help for usage." ;;
  esac
done

ops_section "ops bootstrap"
ops_info "bootstrap is now handled by setup/discovery."

if [[ "${DRY_RUN}" == "true" ]]; then
  exec bash "${_SELF_DIR}/setup.sh" --dry-run
fi

if manifest_exists; then
  if [[ "${FORCE}" != "true" ]]; then
    ops_error ".ops.yaml already exists at: ${OPS_MANIFEST}"
    ops_info "Use --force to merge discovered runtime services, or run: ops setup apply-services --apply"
    exit 1
  fi
  exec bash "${_SELF_DIR}/setup.sh" apply-services --apply
fi

exec bash "${_SELF_DIR}/setup.sh" --apply
