#!/usr/bin/env bash
# .ops-core/lib/backup.sh — Non-destructive .ops.yaml snapshot and rollback helper.
#
# Backs up .ops.yaml to .ops.project/.history/<timestamp>.yaml before any mutating write.
# Provides rollback listing and restore commands.
#
# Usage (from other ops-core scripts):
#   source "${OPS_CORE_ROOT}/lib/backup.sh"
#   ops_backup_manifest             # call before writing .ops.yaml
#   ops_backup_list                 # list available backups
#   ops_backup_restore <timestamp>  # restore a specific backup

set -euo pipefail

# Guard
if [[ "${_OPS_CORE_BACKUP_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_BACKUP_LOADED=1

# Requires init.sh to be sourced first (provides OPS_MANIFEST, OPS_PROJECT_HISTORY_DIR, die, warn, info, ok, ops_timestamp)
_BACKUP_HISTORY_DIR="${OPS_PROJECT_HISTORY_DIR:-${OPS_PROJECT_ROOT}/.ops.project/.history}"
_BACKUP_MAX_ENTRIES=50  # keep at most N backups; prune oldest when exceeded

# ============================================================================
# ops_backup_manifest
# Creates a timestamped copy of .ops.yaml in .ops.project/.history/ before any write.
# Prints the backup path on success.
# ============================================================================
ops_backup_manifest() {
  local manifest="${OPS_MANIFEST}"
  if [[ ! -f "${manifest}" ]]; then
    debug "ops_backup_manifest: no manifest at '${manifest}' — skipping backup"
    return 0
  fi

  ensure_dir "${_BACKUP_HISTORY_DIR}"

  local ts
  ts="$(ops_timestamp | tr ':' '-')"      # colons not valid in filenames on some FS
  local dest="${_BACKUP_HISTORY_DIR}/${ts}.yaml"

  cp "${manifest}" "${dest}"
  ok "Manifest backed up → ${dest}"

  # Prune oldest backups if we've exceeded the retention limit
  _ops_backup_prune
  printf '%s\n' "${dest}"
}

# ============================================================================
# ops_backup_list
# Lists available backups newest-first with index numbers.
# ============================================================================
ops_backup_list() {
  if [[ ! -d "${_BACKUP_HISTORY_DIR}" ]]; then
    info "No backups found (${_BACKUP_HISTORY_DIR} does not exist)."
    return 0
  fi

  local entries
  # Sort reverse-chronologically by filename (timestamps sort lexicographically)
  mapfile -t entries < <(ls -1r "${_BACKUP_HISTORY_DIR}"/*.yaml 2>/dev/null || true)

  if [[ ${#entries[@]} -eq 0 ]]; then
    info "No manifest backups found."
    return 0
  fi

  info "Available backups (newest first):"
  local i=1
  for f in "${entries[@]}"; do
    printf '  %2d)  %s\n' "${i}" "$(basename "${f}")"
    i=$((i + 1))
  done
}

# ============================================================================
# ops_backup_restore <timestamp-or-filename>
# Restores a backup, creating a safety backup of the current manifest first.
# Usage:
#   ops_backup_restore 2026-04-23T12-30-00Z          # by timestamp stem
#   ops_backup_restore 2026-04-23T12-30-00Z.yaml      # with extension
# ============================================================================
ops_backup_restore() {
  local selector="${1:?ops_backup_restore: timestamp or filename required}"
  local src="${_BACKUP_HISTORY_DIR}/${selector%.yaml}.yaml"

  if [[ ! -f "${src}" ]]; then
    die "Backup not found: ${src}"
  fi

  # Safety: back up the current manifest before overwriting
  if [[ -f "${OPS_MANIFEST}" ]]; then
    warn "Creating safety backup of current manifest before restore..."
    ops_backup_manifest >/dev/null
  fi

  cp "${src}" "${OPS_MANIFEST}"
  ok "Manifest restored from: $(basename "${src}")"
}

# ============================================================================
# _ops_backup_prune (internal)
# Removes the oldest backups when count exceeds _BACKUP_MAX_ENTRIES.
# ============================================================================
_ops_backup_prune() {
  local entries
  mapfile -t entries < <(ls -1 "${_BACKUP_HISTORY_DIR}"/*.yaml 2>/dev/null | sort || true)
  local count="${#entries[@]}"
  if [[ ${count} -gt ${_BACKUP_MAX_ENTRIES} ]]; then
    local excess=$(( count - _BACKUP_MAX_ENTRIES ))
    local i
    for (( i = 0; i < excess; i++ )); do
      rm -f "${entries[${i}]}"
      debug "Pruned old backup: ${entries[${i}]}"
    done
  fi
}
