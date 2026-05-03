#!/usr/bin/env bash
# .ops-core/commands/init.sh — Service discovery wizard for ops init (Phase 2+).
#
# Flow:
#   1. Scan project dirs for stack fingerprints (detect.sh)
#   2. Compare to current manifest
#   3. Auto-confirm matches; prompt for mismatches + new services
#   4. Optional depends_on interview per service
#   5. Atomic write: temp → yq update → validate → backup + rename
#
# Flags:
#   --dry-run   Print discovered services + proposed changes; do not write
#   --force     Re-prompt even already-confirmed services
#   --no-deps   Skip the depends_on interview
#   --help

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/detect.sh"
source "${_SELF_DIR}/../lib/interactive.sh"
source "${_SELF_DIR}/../lib/backup.sh"

# ── Flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=false
FORCE=false
NO_DEPS=false

for _arg in "$@"; do
  case "${_arg}" in
    --dry-run) DRY_RUN=true ;;
    --force)   FORCE=true ;;
    --no-deps) NO_DEPS=true ;;
    --help|-h)
      cat <<'EOF'
Usage: ./ops.sh experimental init [--dry-run] [--force] [--no-deps]

Scans the project for services and updates .ops.yaml interactively.

  --dry-run   Preview discovered services; do not write to .ops.yaml
  --force     Re-prompt even services already confirmed
  --no-deps   Skip the depends_on interview step
  --help      Print this help
EOF
      exit 0 ;;
    *) die "Unknown flag: ${_arg}. Use --help." ;;
  esac
done

# ── Preconditions ─────────────────────────────────────────────────────────────
require_manifest
require_bins yq

[[ "${DRY_RUN}" == "false" ]] && interactive_require_tty

# ── Temp dir (cleaned up on exit) ─────────────────────────────────────────────
_TMP_DIR=""
_cleanup_init() { [[ -n "${_TMP_DIR}" ]] && rm -rf "${_TMP_DIR}"; }
trap '_cleanup_init' EXIT INT TERM
_TMP_DIR="$(mktemp -d)"

_TMP_MANIFEST="${_TMP_DIR}/ops.yaml"
_SVC_FRAG="${_TMP_DIR}/svc_fragment.yaml"

# ── Helpers ───────────────────────────────────────────────────────────────────

# Get a field from the WORKING manifest (temp if exists, else original)
_wq() { yq e "$1" "${_TMP_MANIFEST}"; }

# Set a scalar field on the working manifest (in-place)
_wq_set() { yq e -i "$1" "${_TMP_MANIFEST}"; }

# Print a change line for the preview table
_change_line() {
  local action="$1" id="$2" detail="$3"
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    printf '  %-8s  %-16s  %s\n' "${action}" "${id}" "${detail}"
  else
    local color="${OPS_GREEN}"
    [[ "${action}" == "UPDATE" ]] && color="${OPS_YELLOW}"
    [[ "${action}" == "SKIP"   ]] && color="${OPS_DIM}"
    printf '  %s%-8s%s  %-16s  %s\n' "${color}" "${action}" "${OPS_NC}" "${id}" "${detail}"
  fi
}

# Write a new service YAML fragment to $_SVC_FRAG
_write_svc_fragment() {
  local id="$1" name="$2" stack="$3" svc_path="$4" deps="$5" ts="$6"

  # Build YAML depends_on list
  local deps_yaml="[]"
  if [[ -n "${deps}" ]]; then
    deps_yaml="["
    local d first=true
    for d in ${deps}; do
      [[ "${first}" == "false" ]] && deps_yaml+=", "
      deps_yaml+="\"${d}\""
      first=false
    done
    deps_yaml+="]"
  fi

  cat > "${_SVC_FRAG}" <<YAML
id: ${id}
name: "${name}"
stack: ${stack}
path: ${svc_path}
env_files: []
env_policy: dev_file
env_materialization: none
env_output_file: ""
actions:
  start: ""
  stop: ""
  logs: ""
  build: ""
  test: ""
  lint: ""
depends_on: ${deps_yaml}
healthcheck: ""
meta:
  source: init
  confirmed_by_user: true
  generated_at: "${ts}"
YAML
}

# ── Main ──────────────────────────────────────────────────────────────────────
ops_section "ops experimental init"
ops_info "Scanning project (depth=${OPS_SCAN_DEPTH:-2})…"
printf '\n'

# Collect existing manifest service IDs
mapfile -t _MANIFEST_IDS < <(manifest_list_services 2>/dev/null || true)
declare -A _MANIFEST_ID_SET=()
for _id in "${_MANIFEST_IDS[@]+"${_MANIFEST_IDS[@]}"}"; do
  _MANIFEST_ID_SET["${_id}"]=1
done

# Scan project — TSV: id <TAB> rel_path <TAB> stack <TAB> score
declare -a _SCAN_IDS=()
declare -A _SCAN_PATH=() _SCAN_STACK=() _SCAN_SCORE=()
while IFS=$'\t' read -r _id _path _stack _score; do
  [[ -z "${_id}" ]] && continue
  # If duplicate scan ID, prefer higher score
  if [[ -n "${_SCAN_PATH[${_id}]:-}" ]]; then
    (( _score > ${_SCAN_SCORE[${_id}]} )) || continue
  else
    _SCAN_IDS+=("${_id}")
  fi
  _SCAN_PATH["${_id}"]="${_path}"
  _SCAN_STACK["${_id}"]="${_stack}"
  _SCAN_SCORE["${_id}"]="${_score}"
done < <(detect_scan_project)

if [[ "${#_SCAN_IDS[@]}" -eq 0 ]]; then
  ops_warn "No services detected. Check OPS_SCAN_DEPTH (current: ${OPS_SCAN_DEPTH:-2})."
  exit 0
fi

ops_info "Found ${#_SCAN_IDS[@]} candidate(s). Comparing to manifest…"
printf '\n'

# Build the set of all service IDs (manifest + scan) for depends_on validation
declare -a _ALL_KNOWN_IDS=("${_MANIFEST_IDS[@]+"${_MANIFEST_IDS[@]}"}")
for _id in "${_SCAN_IDS[@]}"; do
  printf ' %s ' "${_ALL_KNOWN_IDS[*]+"${_ALL_KNOWN_IDS[*]}"}" | grep -qF " ${_id} " || \
    _ALL_KNOWN_IDS+=("${_id}")
done
_KNOWN_IDS_STR="${_ALL_KNOWN_IDS[*]+"${_ALL_KNOWN_IDS[*]}"}"

# ── Decision loop ─────────────────────────────────────────────────────────────
# Collect proposed changes
declare -a _CHANGES_ADD=()           # new service IDs
declare -A _CHANGES_CONFIRM=()       # id → "stack|name" for auto-confirmed
declare -A _CHANGES_UPDATE_STACK=()  # id → new_stack (when mismatch resolved)
declare -A _CHANGES_UPDATE_NAME=()   # id → new_name
declare -A _CHANGES_DEPS=()          # id → "dep1 dep2 ..."
declare -a _CHANGES_SKIP=()          # already-confirmed, no change

_KNOWN_STACKS=("${OPS_KNOWN_STACKS[@]}")

for _id in "${_SCAN_IDS[@]}"; do
  local_path="${_SCAN_PATH[${_id}]}"
  det_stack="${_SCAN_STACK[${_id}]}"
  det_score="${_SCAN_SCORE[${_id}]}"
  conf_label="$(detect_confidence_label "${det_score}")"

  if [[ -n "${_MANIFEST_ID_SET[${_id}]:-}" ]]; then
    # ── Service exists in manifest ───────────────────────────────────────────
    mft_confirmed="$(_manifest_yq_or_empty ".services[] | select(.id == \"${_id}\") | .confirmed_by_user")"
    mft_stack="$(_manifest_yq_or_empty ".services[] | select(.id == \"${_id}\") | .stack")"
    mft_name="$(_manifest_yq_or_empty ".services[] | select(.id == \"${_id}\") | .name")"

    if [[ "${mft_confirmed}" == "true" && "${FORCE}" == "false" ]]; then
      _CHANGES_SKIP+=("${_id}")
      [[ "${DRY_RUN}" == "true" ]] && \
        _change_line "SKIP" "${_id}" "already confirmed (use --force to re-prompt)"
      continue
    fi

    if [[ "${det_stack}" == "${mft_stack}" ]]; then
      # Stack matches → auto-confirm
      _CHANGES_CONFIRM["${_id}"]="${mft_stack}|${mft_name}"
      [[ "${DRY_RUN}" == "true" ]] && \
        _change_line "UPDATE" "${_id}" "stack=${mft_stack} confirmed=true (auto: fingerprint matches, ${conf_label} confidence)"
    else
      # Mismatch → prompt (unless dry-run)
      if [[ "${DRY_RUN}" == "true" ]]; then
        _change_line "CONFLICT" "${_id}" "manifest=${mft_stack}, detected=${det_stack} (${conf_label}) — will prompt"
        continue
      fi
      interactive_banner "Service: ${_id} (${local_path})"
      printf '  Manifest stack: %s\n  Detected stack: %s (%s confidence, score=%d)\n' \
        "${mft_stack}" "${det_stack}" "${conf_label}" "${det_score}" > /dev/tty

      _menu_items=()
      for s in "${_KNOWN_STACKS[@]}"; do
        _menu_items+=("${s}")
      done
      _idx="$(interactive_menu "Which stack is correct?" "${_menu_items[@]}")"
      chosen_stack="${_KNOWN_STACKS[${_idx}]}"

      _new_name="$(interactive_prompt "  Service name" "${mft_name}")"
      _CHANGES_UPDATE_STACK["${_id}"]="${chosen_stack}"
      _CHANGES_UPDATE_NAME["${_id}"]="${_new_name}"
    fi

  else
    # ── New service not in manifest ──────────────────────────────────────────
    if [[ "${DRY_RUN}" == "true" ]]; then
      _change_line "ADD" "${_id}" "path=${local_path} detected=${det_stack} (${conf_label})"
      continue
    fi

    interactive_banner "New service found: ${_id} (${local_path})"
    printf '  Detected: %s (%s confidence, score=%d)\n' \
      "${det_stack}" "${conf_label}" "${det_score}" > /dev/tty

    if ! interactive_confirm "  Add this service to the manifest?" "y"; then
      _CHANGES_SKIP+=("${_id}")
      continue
    fi

    _new_name="$(interactive_prompt "  Service name" "${_id}")"

    # Stack confirmation or override
    _chosen_stack="${det_stack}"
    if (( det_score < 3 )); then
      printf '  Low confidence — confirming stack.\n' > /dev/tty
      _menu_items=()
      for s in "${_KNOWN_STACKS[@]}"; do _menu_items+=("${s}"); done
      _idx="$(interactive_menu "  Which stack?" "${_menu_items[@]}")"
      _chosen_stack="${_KNOWN_STACKS[${_idx}]}"
    fi

    _CHANGES_ADD+=("${_id}")
    _CHANGES_CONFIRM["${_id}"]="${_chosen_stack}|${_new_name}"
    _SCAN_PATH["${_id}"]="${local_path}"
    _SCAN_STACK["${_id}"]="${_chosen_stack}"
  fi

  # ── depends_on interview ───────────────────────────────────────────────────
  if [[ "${NO_DEPS}" == "false" && "${DRY_RUN}" == "false" ]]; then
    _cur_deps="$(_manifest_yq ".services[] | select(.id == \"${_id}\") | .depends_on[]?" \
      2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)"
    _deps="$(interactive_list_prompt \
      "  depends_on for '${_id}'" "${_KNOWN_IDS_STR}" "${_cur_deps}")"
    [[ -n "${_deps}" ]] && _CHANGES_DEPS["${_id}"]="${_deps}"
  fi
done

# ── Dry-run exit ──────────────────────────────────────────────────────────────
if [[ "${DRY_RUN}" == "true" ]]; then
  printf '\n'
  ops_info "Dry-run complete. No files written."
  exit 0
fi

# ── Nothing to do? ────────────────────────────────────────────────────────────
_total_changes=$(( ${#_CHANGES_ADD[@]} + ${#_CHANGES_DEPS[@]} +
  ${#_CHANGES_UPDATE_STACK[@]} + ${#_CHANGES_UPDATE_NAME[@]} ))
# Also count auto-confirms that are not new adds
for _id in "${!_CHANGES_CONFIRM[@]}"; do
  printf ' %s ' "${_CHANGES_ADD[@]+"${_CHANGES_ADD[@]}"}" | grep -qF " ${_id} " || \
    _total_changes=$(( _total_changes + 1 ))
done

if [[ "${_total_changes}" -eq 0 && "${#_CHANGES_DEPS[@]}" -eq 0 ]]; then
  ops_ok "Already up to date — nothing to write."
  exit 0
fi

# ── Preview ───────────────────────────────────────────────────────────────────
printf '\n'
ops_info "Proposed changes:"
printf '\n'

for _id in "${_SCAN_IDS[@]}"; do
  if [[ -n "${_CHANGES_UPDATE_STACK[${_id}]:-}" ]]; then
    _change_line "UPDATE" "${_id}" \
      "stack → ${_CHANGES_UPDATE_STACK[${_id}]}, name → ${_CHANGES_UPDATE_NAME[${_id}]:-unchanged}"
  elif [[ -n "${_CHANGES_CONFIRM[${_id}]:-}" ]]; then
    if printf ' %s ' "${_CHANGES_ADD[@]+"${_CHANGES_ADD[@]}"}" | grep -qF " ${_id} "; then
      _change_line "ADD" "${_id}" "path=${_SCAN_PATH[${_id}]}, stack=${_SCAN_STACK[${_id}]}"
    else
      _change_line "UPDATE" "${_id}" "confirmed_by_user=true"
    fi
  fi
  if [[ -n "${_CHANGES_DEPS[${_id}]:-}" ]]; then
    printf '           %-16s  depends_on → [%s]\n' "" "${_CHANGES_DEPS[${_id}]}"
  fi
done
printf '\n'

if ! interactive_confirm "Apply these changes?" "y"; then
  ops_info "Aborted. No changes written."
  exit 0
fi

# ── Apply changes ─────────────────────────────────────────────────────────────
ops_info "Writing manifest…"

# Work on a copy
cp "${OPS_MANIFEST}" "${_TMP_MANIFEST}"

_TS="$(ops_timestamp)"
_SEL() { printf '.services[] | select(.id == "%s")' "$1"; }

# Auto-confirms (stack match, no other change)
for _id in "${!_CHANGES_CONFIRM[@]}"; do
  printf ' %s ' "${_CHANGES_ADD[@]+"${_CHANGES_ADD[@]}"}" | grep -qF " ${_id} " && continue
  _wq_set "($(_SEL "${_id}") | .confirmed_by_user) = true"
  _wq_set "($(_SEL "${_id}") | .meta.source) = \"init\""
  _wq_set "($(_SEL "${_id}") | .meta.generated_at) = \"${_TS}\""
done

# Stack/name updates
for _id in "${!_CHANGES_UPDATE_STACK[@]}"; do
  _new_stack="${_CHANGES_UPDATE_STACK[${_id}]}"
  _new_name="${_CHANGES_UPDATE_NAME[${_id}]:-}"
  _wq_set "($(_SEL "${_id}") | .stack) = \"${_new_stack}\""
  [[ -n "${_new_name}" ]] && _wq_set "($(_SEL "${_id}") | .name) = \"${_new_name}\""
  _wq_set "($(_SEL "${_id}") | .confirmed_by_user) = true"
  _wq_set "($(_SEL "${_id}") | .meta.source) = \"init\""
  _wq_set "($(_SEL "${_id}") | .meta.generated_at) = \"${_TS}\""
done

# depends_on updates (loop per dep to avoid inline YAML complexity)
for _id in "${!_CHANGES_DEPS[@]}"; do
  _wq_set "($(_SEL "${_id}") | .depends_on) = []"
  for _dep in ${_CHANGES_DEPS[${_id}]}; do
    _wq_set "($(_SEL "${_id}") | .depends_on) += [\"${_dep}\"]"
  done
done

# New services — append via yq load()
for _id in "${_CHANGES_ADD[@]+"${_CHANGES_ADD[@]}"}"; do
  IFS='|' read -r _stack _name <<< "${_CHANGES_CONFIRM[${_id}]}"
  _write_svc_fragment \
    "${_id}" "${_name}" "${_stack}" "${_SCAN_PATH[${_id}]}" \
    "${_CHANGES_DEPS[${_id}]:-}" "${_TS}"
  _wq_set ".services += [load(\"${_SVC_FRAG}\")]"
done

# ── Validate temp manifest ────────────────────────────────────────────────────
ops_info "Validating…"
if ! OPS_MANIFEST="${_TMP_MANIFEST}" \
     bash "${_SELF_DIR}/validate.sh" --plain > "${_TMP_DIR}/validate.out" 2>&1; then
  ops_error "Validation failed on generated manifest:"
  cat "${_TMP_DIR}/validate.out"
  die "Manifest not written. Fix the errors and retry." 1
fi

# ── Atomic write ──────────────────────────────────────────────────────────────
ops_backup_manifest 2>/dev/null || true
mv "${_TMP_MANIFEST}" "${OPS_MANIFEST}"

ops_ok "Manifest updated → ${OPS_MANIFEST}"
printf '\n'
cat "${_TMP_DIR}/validate.out"
