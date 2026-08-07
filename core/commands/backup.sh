#!/usr/bin/env bash
# .ops/core/commands/backup.sh - Config snapshot and rollback helpers.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"

SUBCMD="${1:-list}"
case "${SUBCMD}" in
  create|list|show|diff|prune|rollback|help|--help|-h) shift || true ;;
  *) SUBCMD="list" ;;
esac

LABEL=""
APPLY=false
SNAPSHOT_ID=""
KEEP_COUNT=20
BACKUP_ROOT="${OPS_PROJECT_HISTORY_DIR}/config"

_usage_backup() {
  cat <<'EOF'
Usage: ops backup create [--label NAME]
       ops backup list
       ops backup show SNAPSHOT_ID
       ops backup diff SNAPSHOT_ID
       ops backup prune [--keep N] [--apply]
       ops rollback SNAPSHOT_ID [--apply]

Snapshots include .ops.project/config/*.json only.
Secrets are never included.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label=*) LABEL="${1#*=}" ;;
    --label)
      shift
      LABEL="${1:-}"
      [[ -n "${LABEL}" ]] || die "--label requires a value" 2
      ;;
    --apply) APPLY=true ;;
    --dry-run) APPLY=false ;;
    --keep=*)
      KEEP_COUNT="${1#*=}"
      [[ "${KEEP_COUNT}" =~ ^[0-9]+$ ]] || die "--keep requires a number" 2
      ;;
    --keep)
      shift
      KEEP_COUNT="${1:-}"
      [[ "${KEEP_COUNT}" =~ ^[0-9]+$ ]] || die "--keep requires a number" 2
      ;;
    --help|-h) SUBCMD="help" ;;
    --*) die "Unknown backup flag: $1" 2 ;;
    *)
      if [[ -z "${SNAPSHOT_ID}" ]]; then
        SNAPSHOT_ID="$1"
      else
        die "Unexpected backup argument: $1" 2
      fi
      ;;
  esac
  shift
done

_safe_label() {
  local raw="${1:-manual}"
  raw="${raw// /-}"
  raw="$(printf '%s' "${raw}" | sed 's/[^A-Za-z0-9_.-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
  [[ -n "${raw}" ]] && printf '%s' "${raw}" || printf 'manual'
}

_snapshot_path() {
  local id="$1"
  printf '%s/%s' "${BACKUP_ROOT}" "${id}"
}

_unique_snapshot_id() {
  local base="$1" id="$1" i=1
  while [[ -e "$(_snapshot_path "${id}")" ]]; do
    i=$((i + 1))
    id="${base}.${i}"
  done
  printf '%s' "${id}"
}

_find_snapshot() {
  local id="$1" path
  [[ -n "${id}" ]] || die "Snapshot id required" 2
  path="$(_snapshot_path "${id}")"
  if [[ -d "${path}" ]]; then
    printf '%s' "${path}"
    return 0
  fi
  path="$(find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name "${id}*" 2>/dev/null | sort | tail -n 1 || true)"
  [[ -n "${path}" && -d "${path}" ]] || die "Backup snapshot not found: ${id}" 2
  printf '%s' "${path}"
}

_config_files() {
  find "${OPS_PROJECT_CONFIG_DIR}" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort || true
}

_backup_create() {
  require_bins jq
  [[ -d "${OPS_PROJECT_CONFIG_DIR}" ]] || die "No config directory found: ${OPS_PROJECT_CONFIG_DIR#${OPS_PROJECT_ROOT}/}" 2

  local label ts id dir file rel files_json='[]'
  label="$(_safe_label "${LABEL:-manual}")"
  ts="$(ops_timestamp | tr ':' '-')"
  id="$(_unique_snapshot_id "${ts}-${label}")"
  dir="$(_snapshot_path "${id}")"

  ensure_dir "${dir}/config"
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    rel="$(basename "${file}")"
    cp "${file}" "${dir}/config/${rel}"
    files_json="$(jq -c --arg file "${rel}" '. + [$file]' <<< "${files_json}")"
  done < <(_config_files)

  if [[ "$(jq 'length' <<< "${files_json}")" == "0" ]]; then
    rm -rf "${dir}"
    die "No config JSON files found to back up." 2
  fi

  jq -n \
    --argjson version 1 \
    --arg id "${id}" \
    --arg label "${label}" \
    --arg created_at "$(ops_timestamp)" \
    --arg source "ops_backup" \
    --arg root ".ops.project/config" \
    --argjson files "${files_json}" \
    '{
      version: $version,
      id: $id,
      label: $label,
      created_at: $created_at,
      source: $source,
      scope: "config",
      root: $root,
      files: $files
    }' > "${dir}/manifest.json"

  ops_ok "Created backup ${id}"
  printf '%s\n' "${id}"
}

_backup_list() {
  ops_section "ops backup list"
  if [[ ! -d "${BACKUP_ROOT}" ]]; then
    ops_info "No config backups found."
    return 0
  fi

  local dir id created label count any=false
  while IFS= read -r dir; do
    [[ -n "${dir}" ]] || continue
    any=true
    id="$(basename "${dir}")"
    if [[ -f "${dir}/manifest.json" ]] && command -v jq >/dev/null 2>&1; then
      created="$(jq -r '.created_at // ""' "${dir}/manifest.json" 2>/dev/null || true)"
      label="$(jq -r '.label // ""' "${dir}/manifest.json" 2>/dev/null || true)"
      count="$(jq -r '.files | length' "${dir}/manifest.json" 2>/dev/null || printf '?')"
    else
      created=""
      label=""
      count="?"
    fi
    printf '  %-36s files=%s label=%s %s\n' "${id}" "${count}" "${label:-<none>}" "${created}"
  done < <(find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)

  [[ "${any}" == "true" ]] || ops_info "No config backups found."
}

_backup_show() {
  require_bins jq
  local dir
  dir="$(_find_snapshot "${SNAPSHOT_ID}")"
  ops_section "ops backup show"
  jq '.' "${dir}/manifest.json"
}

_snapshot_diff_status() {
  local dir="$1" file snap current name status
  while IFS= read -r snap; do
    [[ -n "${snap}" ]] || continue
    name="$(basename "${snap}")"
    current="${OPS_PROJECT_CONFIG_DIR}/${name}"
    if [[ ! -f "${current}" ]]; then
      status="add"
    elif cmp -s "${snap}" "${current}"; then
      status="same"
    else
      status="change"
    fi
    printf '%s\t%s\n' "${status}" "${name}"
  done < <(find "${dir}/config" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)

  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    name="$(basename "${file}")"
    [[ -f "${dir}/config/${name}" ]] || printf 'remove\t%s\n' "${name}"
  done < <(_config_files)
}

_backup_diff() {
  local dir status name
  dir="$(_find_snapshot "${SNAPSHOT_ID}")"
  ops_section "ops backup diff"
  printf 'Snapshot: %s\n' "$(basename "${dir}")"
  printf 'Target: %s\n\n' "${OPS_PROJECT_CONFIG_DIR#${OPS_PROJECT_ROOT}/}"
  printf '  %-8s %s\n' "STATUS" "FILE"
  _snapshot_diff_status "${dir}" | while IFS=$'\t' read -r status name; do
    printf '  %-8s %s\n' "${status}" "${name}"
  done
}

_backup_prune() {
  [[ "${KEEP_COUNT}" -ge 0 ]] || die "--keep must be 0 or greater" 2
  ops_section "ops backup prune"
  if [[ ! -d "${BACKUP_ROOT}" ]]; then
    ops_info "No config backups found."
    return 0
  fi

  local entries=() remove=() keep="${KEEP_COUNT}" i excess dir
  mapfile -t entries < <(find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
  excess=$(( ${#entries[@]} - keep ))
  if [[ "${excess}" -le 0 ]]; then
    ops_info "Nothing to prune. Backups: ${#entries[@]}, keep: ${keep}."
    return 0
  fi

  for (( i = keep; i < ${#entries[@]}; i++ )); do
    remove+=("${entries[$i]}")
  done

  printf 'Backups: %d, keep: %d, prune: %d\n' "${#entries[@]}" "${keep}" "${#remove[@]}"
  for dir in "${remove[@]+"${remove[@]}"}"; do
    printf '  %s\n' "$(basename "${dir}")"
  done

  if [[ "${APPLY}" != "true" ]]; then
    printf '\n'
    ops_info "Preview only. Re-run with --apply to delete old backups."
    return 0
  fi

  for dir in "${remove[@]+"${remove[@]}"}"; do
    rm -rf "${dir}"
  done
  ops_ok "Pruned ${#remove[@]} old backup(s)."
}

_rollback() {
  local dir status name safety_id
  dir="$(_find_snapshot "${SNAPSHOT_ID}")"

  ops_section "ops rollback"
  printf 'Snapshot: %s\n' "$(basename "${dir}")"
  printf 'Target: %s\n\n' "${OPS_PROJECT_CONFIG_DIR#${OPS_PROJECT_ROOT}/}"
  printf '  %-8s %s\n' "STATUS" "FILE"
  _snapshot_diff_status "${dir}" | while IFS=$'\t' read -r status name; do
    printf '  %-8s %s\n' "${status}" "${name}"
  done

  if [[ "${APPLY}" != "true" ]]; then
    printf '\n'
    ops_info "Preview only. Re-run with --apply to restore this snapshot."
    return 0
  fi

  LABEL="pre-rollback"
  safety_id="$(_backup_create | tail -n 1)"
  ops_info "Safety backup created: ${safety_id}"

  ensure_dir "${OPS_PROJECT_CONFIG_DIR}"
  find "${OPS_PROJECT_CONFIG_DIR}" -maxdepth 1 -type f -name '*.json' -delete 2>/dev/null || true
  cp "${dir}/config/"*.json "${OPS_PROJECT_CONFIG_DIR}/"
  ops_ok "Restored config from $(basename "${dir}")"
}

case "${SUBCMD}" in
  help|--help|-h) _usage_backup ;;
  create) _backup_create ;;
  list) _backup_list ;;
  show) _backup_show ;;
  diff) _backup_diff ;;
  prune) _backup_prune ;;
  rollback) _rollback ;;
esac
