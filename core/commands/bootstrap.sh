#!/usr/bin/env bash
# .ops/core/commands/bootstrap.sh - Compatibility wrapper for config-first setup.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"

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

`setup` is now the project initializer and discovery engine.
`--force` is accepted for compatibility and maps to config-first setup apply.
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

[[ "${FORCE}" == "true" ]] && ops_info "--force accepted for compatibility; running config-first setup apply."

exec bash "${_SELF_DIR}/setup.sh" --apply
