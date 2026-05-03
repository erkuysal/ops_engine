#!/usr/bin/env bash
# .ops-core/commands/update.sh — Self-healing manifest incremental updater.
#
# Scans the workspace directly and merges newly discovered services into the
# existing .ops.yaml.
#
# Flags:
#   --apply    Write the changes to .ops.yaml (with backup).
#
# Usage: ops experimental update [--apply]

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/backup.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/detect.sh"

APPLY=false

for _arg in "$@"; do
  case "${_arg}" in
    --apply) APPLY=true ;;
    --help|-h)
      cat <<'EOF'
Usage: ./ops.sh experimental update [--apply]

Scans the workspace for newly added services and merges them into .ops.yaml
without removing existing comments or manual configuration.

Flags:
  --apply      Write the changes to .ops.yaml (auto-backup created).
EOF
      exit 0
      ;;
    *) die "Unknown flag: ${_arg}. Use --help for usage." ;;
  esac
done

require_bins yq
require_manifest

ops_section "ops experimental update"

_generated_at="$(ops_timestamp)"

_humanize_id() {
  local raw="$1"
  awk -v value="${raw}" 'BEGIN {
    n = split(value, parts, /[_-]+/)
    first = 1
    for (i = 1; i <= n; i++) {
      part = parts[i]
      if (part == "") continue
      if (!first) printf " "
      printf "%s%s", toupper(substr(part, 1, 1)), tolower(substr(part, 2))
      first = 0
    }
  }'
}

_write_service() {
  local id="$1" name="$2" stack="$3" path="$4"
  local has_runtime=true
  [[ "${id}" == "api_core" ]] && has_runtime=false

  printf '  - id: %s\n' "${id}"
  printf '    name: "%s"\n' "${name}"
  printf '    stack: %s\n' "${stack}"
  printf '    path: %s\n' "${path}"
  printf '    env_files: []\n'
  printf '    env_policy: dev_file\n'
  printf '    env_materialization: none\n'
  printf '    env_output_file: ""\n'
  printf '    actions:\n'
  printf '      start: ""\n'
  printf '      stop: ""\n'
  printf '      logs: ""\n'
  printf '      build: ""\n'
  printf '      test: ""\n'
  printf '      lint: ""\n'
  printf '    depends_on: []\n'
  printf '    healthcheck: ""\n'
  if [[ "${has_runtime}" != true ]]; then
    printf '    # note: api_core is a shared library; start/stop/logs are intentionally empty.\n'
  fi
  printf '    meta:\n'
  printf '      source: detect_scan_project\n'
  printf '      confirmed_by_user: false\n'
  printf '      generated_at: "%s"\n' "${_generated_at}"
  printf '\n'
}

mapfile -t EXISTING_SERVICES < <(manifest_list_services | sort)
declare -A EXISTING_MAP=()
for s in "${EXISTING_SERVICES[@]+"${EXISTING_SERVICES[@]}"}"; do
  [[ -n "${s}" ]] && EXISTING_MAP["${s}"]=1
done

declare -A DISCOVERED_MAP=()
declare -A DISCOVERED_META=()

while IFS=$'\t' read -r id rel_path stack score; do
  [[ -z "${id}" ]] && continue
  DISCOVERED_MAP["${id}"]=1
  DISCOVERED_META["${id}"]="${rel_path}	${stack}"
done < <(detect_scan_project)

ADDED=()
for id in "${!DISCOVERED_MAP[@]}"; do
  if [[ -z "${EXISTING_MAP[${id}]:-}" ]]; then
    ADDED+=("${id}")
  fi
done

MISSING=()
for id in "${!EXISTING_MAP[@]}"; do
  if [[ -z "${DISCOVERED_MAP[${id}]:-}" ]]; then
    MISSING+=("${id}")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  ops_warn "The following services exist in .ops.yaml but were not detected from the workspace scan:"
  for id in "${MISSING[@]}"; do
    ops_warn "  - ${id} (Will NOT be deleted automatically)"
  done
  printf '\n'
fi

if [[ ${#ADDED[@]} -eq 0 ]]; then
  ops_ok "Manifest is up to date. No new services found."
  exit 0
fi

ops_info "Found ${#ADDED[@]} new service(s) to add:"
for id in "${ADDED[@]}"; do
  ops_info "  + ${id}"
done
printf '\n'

_TMP_NEW_YAML="${OPS_MANIFEST}.new.$$"
_TMP_MERGED_YAML="${OPS_MANIFEST}.merged.$$"
trap 'rm -f "${_TMP_NEW_YAML}" "${_TMP_MERGED_YAML}"' EXIT

echo "services:" > "${_TMP_NEW_YAML}"
for id in "${ADDED[@]}"; do
  meta="${DISCOVERED_META[${id}]}"
  path="$(printf '%s' "${meta}" | cut -f1)"
  stack="$(printf '%s' "${meta}" | cut -f2)"
  _write_service "${id}" "$(_humanize_id "${id}")" "${stack}" "${path}" >> "${_TMP_NEW_YAML}"
done

ops_debug "Splicing new services via yq AST merge..."
if ! yq eval-all 'select(fileIndex == 0).services += select(fileIndex == 1).services | select(fileIndex == 0)' "${OPS_MANIFEST}" "${_TMP_NEW_YAML}" > "${_TMP_MERGED_YAML}"; then
  ops_error "Failed to merge YAML AST."
  exit 1
fi

ops_info "Proposed Changes:"
if command -v git >/dev/null 2>&1; then
  git diff --no-index "${OPS_MANIFEST}" "${_TMP_MERGED_YAML}" --color=always || true
else
  diff -u "${OPS_MANIFEST}" "${_TMP_MERGED_YAML}" || true
fi
printf '\n'

if [[ "${APPLY}" == "true" ]]; then
  ops_info "Applying changes..."
  ops_backup_manifest > /dev/null
  mv "${_TMP_MERGED_YAML}" "${OPS_MANIFEST}"
  ops_ok "Manifest updated → ${OPS_MANIFEST}"
else
  ops_info "Preview only. Run with --apply to save these changes."
fi
