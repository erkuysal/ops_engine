#!/usr/bin/env bash
# .ops/core/commands/update.sh - Compatibility wrapper for setup apply-services.

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
  ops setup apply-services
  ops setup apply-services --apply

`setup apply-services` now owns discovery-backed service merging.
EOF
      exit 0
      ;;
    *) die "Unknown flag: ${_arg}. Use --help for usage." ;;
  esac
done

ops_section "ops update"
ops_info "update is now handled by setup apply-services."

if [[ "${APPLY}" == "true" ]]; then
  exec bash "${_SELF_DIR}/setup.sh" apply-services --apply
fi

exec bash "${_SELF_DIR}/setup.sh" apply-services
