#!/usr/bin/env bash
# .ops/core/commands/rollback.sh - Direct alias for config rollback.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${_SELF_DIR}/backup.sh" rollback "$@"
