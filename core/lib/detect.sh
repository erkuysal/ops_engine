#!/usr/bin/env bash
# .ops-core/lib/detect.sh — Probe-based stack fingerprint engine for ops init.
#
# Each stack probe is stored as a small script under .ops/core/probes/.
# Confidence levels: HIGH=3  MEDIUM=2  LOW=1
# Score >= 3 → unambiguous; 1-2 → prompt; 0 → no recognizable stack found.
#
# Requires: init.sh (sourced first)

set -euo pipefail
if [[ "${_OPS_CORE_DETECT_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_DETECT_LOADED=1

OPS_PROBES_DIR="${OPS_CORE_ROOT}/probes"
export OPS_PROBES_DIR

# Directories skipped during project scan
_DETECT_SKIP_DIRS=(
  .git node_modules __pycache__ vendor dist build .cache .next
  .ops-core .ops _build deps .elixir_ls priv/static coverage
  '*.egg-info' '.tox' 'venv' '.venv' 'env'
)

# ==========================================================================
# PROBE LOADER
# ============================================================================

_DETECT_PROBES_LOADED=0
_detect_load_probes() {
  [[ "${_DETECT_PROBES_LOADED}" == "1" ]] && return 0
  _DETECT_PROBES_LOADED=1

  local probe_file
  for probe_file in "${OPS_PROBES_DIR}"/*.sh; do
    [[ -f "${probe_file}" ]] || continue
    # shellcheck source=/dev/null
    source "${probe_file}"
  done
}

# Score a directory for stack detection.
# Prints "<stack> <score>" to stdout; score 0 means no recognizable stack.
# Usage: detect_stack_for_dir <absolute-dir-path>
detect_stack_for_dir() {
  local dir="${1:?detect_stack_for_dir: directory required}"
  [[ ! -d "${dir}" ]] && return 1

  _detect_load_probes

  local best_stack="custom" best_score=0
  local probe_file probe_stack probe_score
  local probe_name
  for probe_file in "${OPS_PROBES_DIR}"/*.sh; do
    [[ -f "${probe_file}" ]] || continue
    probe_name="$(basename "${probe_file}" .sh)"
    probe_name="${probe_name//-/_}"
    probe_stack=""
    probe_score=0
    if declare -F "probe_${probe_name}_score_dir" >/dev/null 2>&1; then
      probe_score="$("probe_${probe_name}_score_dir" "${dir}" 2>/dev/null || printf '0')"
    fi
    if [[ "${probe_score}" =~ ^[0-9]+$ ]] && {
      (( probe_score > best_score )) || \
      { (( probe_score == best_score )) && [[ "${best_stack}" == "docker" && "${probe_name}" != "docker" ]]; }; 
    }; then
      best_score="${probe_score}"
      probe_stack="$(declare -F "probe_${probe_name}_stack_id" >/dev/null 2>&1 && probe_${probe_name}_stack_id || printf '')"
      [[ -n "${probe_stack}" ]] && best_stack="${probe_stack}"
    fi
  done

  printf '%s %d' "${best_stack}" "${best_score}"
}

# ============================================================================
# PROJECT SCAN
# ============================================================================

# Scan all candidate service directories under OPS_PROJECT_ROOT.
# Emits one TSV line per detected service:
#   id <TAB> rel_path <TAB> stack <TAB> score
#
# Skips directories with score=0 (no recognizable files).
# Max scan depth controlled by OPS_SCAN_DEPTH (default: 2).
#
# Usage: detect_scan_project
detect_scan_project() {
  local max_depth="${OPS_SCAN_DEPTH:-2}"

  # Build -name prune list for find
  local prune_expr=()
  local d
  for d in "${_DETECT_SKIP_DIRS[@]}"; do
    prune_expr+=(-o -name "${d}")
  done

  local dir result stack score rel_path id
  while IFS= read -r dir; do
    [[ ! -d "${dir}" ]] && continue

    result="$(detect_stack_for_dir "${dir}")"
    read -r stack score <<< "${result}"

    (( score == 0 )) && continue   # skip unrecognized dirs

    rel_path="${dir#"${OPS_PROJECT_ROOT}/"}"
    id="$(basename "${dir}")"

    printf '%s\t%s\t%s\t%d\n' "${id}" "${rel_path}" "${stack}" "${score}"
  done < <(
    find "${OPS_PROJECT_ROOT}" \
      -mindepth 1 -maxdepth "${max_depth}" \
      \( -name '.git' "${prune_expr[@]}" \) -prune \
      -o -type d -print \
      2>/dev/null
  )
}

# ============================================================================
# HELPERS
# ============================================================================

# Print a human-readable confidence label for a score.
detect_confidence_label() {
  local score="${1:-0}"
  if   (( score >= 3 )); then printf 'high'
  elif (( score >= 1 )); then printf 'low'
  else                         printf 'none'
  fi
}
