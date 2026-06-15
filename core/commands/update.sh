#!/usr/bin/env bash
# .ops/core/commands/update.sh - Compatibility wrapper for setup.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"

APPLY=false

for _arg in "$@"; do
  case "${_arg}" in
    --apply) APPLY=true ;;
    --help|-h)
      cat <<'EOF'
Usage: ops update [--apply]

Compatibility wrapper for:
  ops setup --dry-run
  ops setup --apply

`setup` now owns discovery-backed config refresh.
EOF
      exit 0
      ;;
    *) die "Unknown flag: ${_arg}. Use --help for usage." ;;
  esac
done

ops_section "ops update"
ops_info "update is now handled by config-first setup."

if [[ "${APPLY}" == "true" ]]; then
  exec bash "${_SELF_DIR}/setup.sh" --apply
fi

exec bash "${_SELF_DIR}/setup.sh" --dry-run
