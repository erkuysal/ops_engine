#!/usr/bin/env bash
# .ops/core/commands/describe.sh — Machine-readable command capability manifest.
#
# Reads core/capabilities.json (package-owned, hand-maintained) so a caller —
# human or agent — can discover what ops can do, and how safe each command is
# to call, without parsing --help text or command source.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/output.sh"

CAPABILITIES_FILE="${OPS_CORE_ROOT}/capabilities.json"
TARGET=""
JSON=false

_usage_describe() {
  cat <<'EOF'
Usage: ops describe [COMMAND] [--json]

List every ops command with its summary and safety tier, or show one
command's full entry when COMMAND is given.

Safety tiers:
  read_only           never mutates
  preview_by_default  mutates only with an explicit --apply (safe by default)
  live_by_default     mutates immediately unless --dry-run is passed
  always_mutates       no preview mechanism at all
  plan_only            execution is not implemented yet, regardless of flags

Examples:
  ops describe
  ops describe --json
  ops describe ship
  ops describe ship --json
EOF
}

for arg in "$@"; do
  case "${arg}" in
    --json) JSON=true ;;
    help|--help|-h) _usage_describe; exit 0 ;;
    -*) die "Unknown describe flag: ${arg}" 2 ;;
    *)
      [[ -z "${TARGET}" ]] || die "Multiple commands not supported: '${TARGET}' and '${arg}'" 2
      TARGET="${arg}"
      ;;
  esac
done

[[ -f "${CAPABILITIES_FILE}" ]] || die "Capability manifest not found: ${CAPABILITIES_FILE}" 2
require_bins jq

_select_filter() {
  if [[ -n "${TARGET}" ]]; then
    printf '.commands | map(select(.id == $target or ((.aliases // []) | index($target)) != null))'
  else
    printf '.commands'
  fi
}

SELECTED="$(jq -c --arg target "${TARGET}" "$(_select_filter)" "${CAPABILITIES_FILE}")"

if [[ -n "${TARGET}" ]] && [[ "$(printf '%s' "${SELECTED}" | jq 'length')" -eq 0 ]]; then
  die "Unknown command: '${TARGET}'. Run 'ops describe' for the full list." 2
fi

if [[ "${JSON}" == "true" ]]; then
  jq -n --argjson commands "${SELECTED}" '{commands: $commands}' | ops_json_envelope "describe"
  exit 0
fi

if [[ -n "${TARGET}" ]]; then
  printf '%s\n' "${SELECTED}" | jq -r '.[] |
    "\(.id)" + (if (.aliases // []) != [] then " (aliases: " + ((.aliases // []) | join(", ")) + ")" else "" end) + "\n" +
    "  summary: \(.summary)\n" +
    "  status:  \(.status)\n" +
    "  safety:  \(.safety)\n" +
    (if .notes then "  notes:   \(.notes)\n" else "" end) +
    (if .script then "  script:  \(.script)\n" else "" end) +
    (if .doc then "  doc:     \(.doc)\n" else "" end)'
  exit 0
fi

ops_section "ops commands"
printf '%s\n' "${SELECTED}" | jq -r '.[] |
  .id + (if (.aliases // []) != [] then " (" + ((.aliases // []) | join(", ")) + ")" else "" end) as $label |
  "  \($label)\n    \(.summary)\n    safety: \(.safety)\n"'
printf 'Run '\''ops describe COMMAND'\'' for details, or '\''ops describe --json'\'' for the full manifest.\n'
