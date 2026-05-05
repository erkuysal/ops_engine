#!/usr/bin/env bash
# .ops/core/commands/init.sh - Compatibility wrapper for setup.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"

DRY_RUN=false
FORCE=false
NO_DEPS=false

for _arg in "$@"; do
  case "${_arg}" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
    --no-deps) NO_DEPS=true ;;
    --help|-h)
      cat <<'EOF'
Usage: ops init [--dry-run] [--force] [--no-deps]

Compatibility wrapper for discovery-backed setup.

Mappings:
  --dry-run          -> ops setup apply-services
  default           -> ops setup apply-services --apply
  --force           -> adds --interactive for ambiguous setup decisions
  --no-deps         -> accepted for compatibility; dependency interview moved out of init
EOF
      exit 0
      ;;
    *) die "Unknown flag: ${_arg}. Use --help." ;;
  esac
done

ops_section "ops init"
ops_info "init is now handled by setup apply-services."
if [[ "${NO_DEPS}" == "true" ]]; then
  ops_info "--no-deps accepted for compatibility; dependency interviews are not part of this wrapper."
fi

args=(apply-services)
[[ "${FORCE}" == "true" ]] && args+=(--interactive)
[[ "${DRY_RUN}" != "true" ]] && args+=(--apply)

exec bash "${_SELF_DIR}/setup.sh" "${args[@]}"
