#!/usr/bin/env bash
# .ops-core/commands/validate.sh — Four-pass manifest validator.
#
# Passes:
#   1) Syntax    — yq can parse .ops.yaml without error
#   2) Structural — required top-level keys + types
#   3) Semantic  — duplicate IDs, unknown stacks, depends_on refs, env_policy values
#   4) Filesystem — service paths exist, env_files exist when policy requires them
#
# Diagnostics are collected throughout all passes and printed grouped by severity.
# Exit codes:
#   0   validation passed (may have warnings/hints)
#   1   one or more ERRORs found
#   2   config error (missing .ops.yaml or yq)
#
# Usage: ./ops.sh experimental validate [--plain]

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/init.sh
source "${_SELF_DIR}/../lib/init.sh"
# shellcheck source=../lib/logger.sh
source "${_SELF_DIR}/../lib/logger.sh"
# shellcheck source=../lib/manifest.sh
source "${_SELF_DIR}/../lib/manifest.sh"
# shellcheck source=../lib/settings.sh
source "${_SELF_DIR}/../lib/settings.sh"
# shellcheck source=../lib/setup.sh
source "${_SELF_DIR}/../lib/setup.sh"
# shellcheck source=../lib/graph.sh
source "${_SELF_DIR}/../lib/graph.sh"

# ── Argument parsing ─────────────────────────────────────────────────────────
for _arg in "$@"; do
  case "${_arg}" in
    --plain)   OPS_PLAIN=true ;;
    --help|-h)
      printf 'Usage: ./ops.sh experimental validate [--plain]\n'
      printf 'Validates .ops.yaml through a five-pass pipeline.\n'
      printf 'Exit 0 = passed (warnings OK), exit 1 = errors found.\n'
      exit 0
      ;;
    *) die "Unknown flag: ${_arg}. Use --help for usage." ;;
  esac
done

# ── Preconditions ─────────────────────────────────────────────────────────────
require_bins yq
require_manifest

# ── Diagnostic collector ──────────────────────────────────────────────────────
_ERRORS=()
_WARNINGS=()
_HINTS=()

_err()  { _ERRORS+=("${1}"); }
_warn() { _WARNINGS+=("${1}"); }
_hint() { _HINTS+=("${1}"); }

# ── Formatting helpers ────────────────────────────────────────────────────────
_print_diag() {
  local tag="$1" color="$2"
  shift 2
  local item
  for item in "$@"; do
    if [[ "${OPS_PLAIN}" == "true" ]]; then
      printf '[%s]  %s\n' "${tag}" "${item}"
    else
      printf '%s[%s]%s  %s\n' "${color}" "${tag}" "${OPS_NC}" "${item}"
    fi
  done
}

# ── PASS 1: Syntax ────────────────────────────────────────────────────────────
_pass1_syntax() {
  ops_step 1 5 "Syntax check (yq parse)"
  local err_output
  if ! err_output="$(yq e '.' "${OPS_MANIFEST}" > /dev/null 2>&1)"; then
    _err "Syntax — yq could not parse '${OPS_MANIFEST}': ${err_output}"
    return 0   # continue collecting; caller checks _ERRORS
  fi
  debug "Pass 1: syntax OK"
}

# ── PASS 2: Structural ────────────────────────────────────────────────────────
_pass2_structural() {
  ops_step 2 5 "Structural validation (required sections)"

  # version
  local ver
  ver="$(_manifest_yq_or_empty '.version')"
  if [[ -z "${ver}" || "${ver}" == "null" ]]; then
    _err "version — required field missing or null"
  elif [[ "${ver}" != "1" ]]; then
    _warn "version — expected \"1\", found \"${ver}\" (future schema versions may differ)"
  fi

  # project block
  local project_check
  project_check="$(_manifest_yq_or_empty '.project')"
  if [[ -z "${project_check}" || "${project_check}" == "null" ]]; then
    _err "project — required block missing"
  else
    local project_name
    project_name="$(_manifest_yq_or_empty '.project.name')"
    if [[ -z "${project_name}" || "${project_name}" == "null" ]]; then
      _warn "project.name — not set (recommended for identification)"
    fi
  fi

  # services block
  local svc_type
  svc_type="$(_manifest_yq '. | .services | tag')" 2>/dev/null || svc_type=""
  local svc_count
  svc_count="$(_manifest_yq '.services | length')" 2>/dev/null || svc_count="0"

  if [[ -z "${svc_count}" || "${svc_count}" == "null" || "${svc_count}" == "0" ]]; then
    _err "services — required list is missing or empty"
  elif [[ "${svc_type}" != "!!seq" ]]; then
    _err "services — must be a YAML sequence (list), found type: ${svc_type}"
  fi

  debug "Pass 2: structural OK (${svc_count} services)"
}

# ── PASS 3: Semantic ──────────────────────────────────────────────────────────
_pass3_semantic() {
  ops_step 3 5 "Semantic validation (IDs, stacks, dependencies)"

  # Collect all service IDs
  mapfile -t _ALL_IDS < <(_manifest_yq '.services[].id' 2>/dev/null || true)

  # Duplicate ID detection
  declare -A _id_seen=()
  local id
  for id in "${_ALL_IDS[@]+"${_ALL_IDS[@]}"}"; do
    if [[ -z "${id}" || "${id}" == "null" ]]; then
      _err "services — a service entry is missing the required 'id' field"
      continue
    fi
    if [[ -n "${_id_seen[${id}]:-}" ]]; then
      _err "services — duplicate service id: '${id}'"
    fi
    _id_seen["${id}"]=1
  done

  # Per-service semantic checks
  local stack env_policy env_mat
  for id in "${_ALL_IDS[@]+"${_ALL_IDS[@]}"}"; do
    [[ -z "${id}" || "${id}" == "null" ]] && continue

    # Stack
    stack="$(_manifest_yq_or_empty ".services[] | select(.id == \"${id}\") | .stack")"
    if [[ -z "${stack}" || "${stack}" == "null" ]]; then
      _err "services.${id}.stack — required field missing"
    else
      local valid_stack=false
      local s
      for s in "${OPS_KNOWN_STACKS[@]}"; do
        [[ "${stack}" == "${s}" ]] && valid_stack=true && break
      done
      if [[ "${valid_stack}" == false ]]; then
        _err "services.${id}.stack — unknown stack '${stack}'. Known: ${OPS_KNOWN_STACKS[*]}"
      fi
    fi

    # Path field exists (not empty)
    local svc_path
    svc_path="$(_manifest_yq_or_empty ".services[] | select(.id == \"${id}\") | .path")"
    if [[ -z "${svc_path}" || "${svc_path}" == "null" ]]; then
      _err "services.${id}.path — required field missing"
    fi

    # env_policy
    env_policy="$(_manifest_yq_or_empty ".services[] | select(.id == \"${id}\") | .env_policy")"
    if [[ -n "${env_policy}" && "${env_policy}" != "null" ]]; then
      local valid_policy=false
      local p
      for p in "${OPS_VALID_ENV_POLICIES[@]}"; do
        [[ "${env_policy}" == "${p}" ]] && valid_policy=true && break
      done
      [[ "${valid_policy}" == false ]] && \
        _err "services.${id}.env_policy — invalid value '${env_policy}'. Valid: ${OPS_VALID_ENV_POLICIES[*]}"
    fi

    # env_materialization
    env_mat="$(_manifest_yq_or_empty ".services[] | select(.id == \"${id}\") | .env_materialization")"
    if [[ -n "${env_mat}" && "${env_mat}" != "null" ]]; then
      local valid_mat=false
      local m
      for m in "${OPS_VALID_ENV_MATERIALIZATIONS[@]}"; do
        [[ "${env_mat}" == "${m}" ]] && valid_mat=true && break
      done
      [[ "${valid_mat}" == false ]] && \
        _err "services.${id}.env_materialization — invalid value '${env_mat}'. Valid: ${OPS_VALID_ENV_MATERIALIZATIONS[*]}"
    fi

    # depends_on references
    local dep
    while IFS= read -r dep; do
      [[ -z "${dep}" || "${dep}" == "null" ]] && continue
      if [[ -z "${_id_seen[${dep}]:-}" ]]; then
        _err "services.${id}.depends_on — references unknown service id: '${dep}'"
      fi
    done < <(_manifest_yq ".services[] | select(.id == \"${id}\") | .depends_on[]?" 2>/dev/null || true)

    # Actions hint: empty actions are expected in Phase 0-2 but hint for awareness
    local start_action
    start_action="$(_manifest_yq_or_empty ".services[] | select(.id == \"${id}\") | .actions.start")"
    if [[ -z "${start_action}" || "${start_action}" == "null" ]]; then
      _hint "services.${id}.actions.start — empty (fill in before Phase 3 execution)"
    fi
  done

  # Run dependency graph cycle check
  graph_cycle_check

  debug "Pass 3: semantic checks complete"
}

# ── PASS 4: Filesystem ────────────────────────────────────────────────────────
_pass4_filesystem() {
  ops_step 4 5 "Filesystem validation (paths, env files)"

  local id svc_path abs_path env_policy
  for id in "${_ALL_IDS[@]+"${_ALL_IDS[@]}"}"; do
    [[ -z "${id}" || "${id}" == "null" ]] && continue

    # Service path existence
    svc_path="$(_manifest_yq_or_empty ".services[] | select(.id == \"${id}\") | .path")"
    if [[ -n "${svc_path}" && "${svc_path}" != "null" ]]; then
      abs_path="${OPS_PROJECT_ROOT}/${svc_path}"
      if [[ ! -d "${abs_path}" ]]; then
        _err "services.${id}.path — directory not found: '${svc_path}'"
      fi
    fi

    # env_files existence (only when env_policy requires local files)
    env_policy="$(_manifest_yq_or_empty ".services[] | select(.id == \"${id}\") | .env_policy")"
    if [[ "${env_policy}" == "dev_file" || "${env_policy}" == "mixed" ]]; then
      local ef
      while IFS= read -r ef; do
        [[ -z "${ef}" || "${ef}" == "null" ]] && continue
        local abs_ef="${OPS_PROJECT_ROOT}/${ef}"
        if [[ ! -f "${abs_ef}" ]]; then
          _warn "services.${id}.env_files — file not found: '${ef}' (required when env_policy=${env_policy})"
        fi
      done < <(_manifest_yq ".services[] | select(.id == \"${id}\") | .env_files[]?" 2>/dev/null || true)
    fi

    # Action script paths: if an action value looks like a shell script path, check it
    local action_val
    for action_name in start stop logs build test lint; do
      action_val="$(_manifest_yq_or_empty ".services[] | select(.id == \"${id}\") | .actions.${action_name}")"
      if [[ -n "${action_val}" && "${action_val}" != "null" && "${action_val}" == *.sh ]]; then
        local abs_action="${OPS_PROJECT_ROOT}/${action_val}"
        if [[ ! -f "${abs_action}" ]]; then
          _err "services.${id}.actions.${action_name} — script not found: '${action_val}'"
        elif [[ ! -x "${abs_action}" ]]; then
          _warn "services.${id}.actions.${action_name} — script not executable: '${action_val}'"
        fi
      fi
    done
  done

  # Global env files
  local gef
  local _global_env_count
  _global_env_count="$(_manifest_yq '.project.global_env_files | length' 2>/dev/null || echo 0)"
  while IFS= read -r gef; do
    [[ -z "${gef}" || "${gef}" == "null" ]] && continue
    local abs_gef="${OPS_PROJECT_ROOT}/${gef}"
    if [[ ! -f "${abs_gef}" ]]; then
      _warn "project.global_env_files — file not found: '${gef}' (expected at runtime)"
    fi
  done < <(_manifest_yq '.project.global_env_files[]?' 2>/dev/null || true)

  # Env-layer hint: service uses dev_file policy but has no env files at any layer
  if [[ "${_global_env_count}" == "0" ]]; then
    for id in "${_ALL_IDS[@]+"${_ALL_IDS[@]}"}"; do
      [[ -z "${id}" || "${id}" == "null" ]] && continue
      local svc_pol svc_ef_count
      svc_pol="$(_manifest_yq_or_empty ".services[] | select(.id == \"${id}\") | .env_policy")"
      [[ -z "${svc_pol}" || "${svc_pol}" == "null" ]] && svc_pol="dev_file"
      svc_ef_count="$(_manifest_yq ".services[] | select(.id == \"${id}\") | .env_files | length" 2>/dev/null || echo 0)"
      if [[ "${svc_pol}" == "dev_file" && ("${svc_ef_count}" == "0" || -z "${svc_ef_count}") ]]; then
        _hint "services.${id} — env_policy=dev_file but no env files declared at any layer"
      fi
    done
  fi

  debug "Pass 4: filesystem checks complete"
}

# ── PASS 5: Overrides ─────────────────────────────────────────────────────────
_pass5_overrides() {
  ops_step 5 5 "Overrides validation (executable bit, shebang)"

  local cmd_dir="${OPS_PROJECT_ROOT}/.ops/commands"
  if [[ -d "${cmd_dir}" ]]; then
    local override_file
    while IFS= read -r override_file; do
      [[ -z "${override_file}" ]] && continue
      
      # Check executable bit
      if [[ ! -x "${override_file}" ]]; then
        _err "Overrides — not executable: ${override_file#${OPS_PROJECT_ROOT}/} (run chmod +x)"
      fi
      
      # Check shebang
      local shebang
      shebang="$(head -n 1 "${override_file}" 2>/dev/null || true)"
      if [[ "${shebang}" != "#!/usr/bin/env bash" && "${shebang}" != "#!/bin/bash" ]]; then
        _warn "Overrides — missing or non-bash shebang: ${override_file#${OPS_PROJECT_ROOT}/} (expected #!/usr/bin/env bash)"
      fi
      
    done < <(find "${cmd_dir}" -type f -name "*.sh" 2>/dev/null || true)
  fi

  if settings_exists && ! settings_validate >/dev/null 2>&1; then
    _err "Settings — invalid .ops.yaml settings section"
  fi

  if setup_exists && ! setup_validate >/dev/null 2>&1; then
    _err "Setup — invalid .ops.yaml setup section"
  fi

  local profile_name
  while IFS= read -r profile_name; do
    [[ -z "${profile_name}" || "${profile_name}" == "null" ]] && continue
    if ! setup_profile_validate "${profile_name}" >/dev/null 2>&1; then
      _err "Profile — invalid .ops.yaml profiles.${profile_name} section"
    fi
  done < <(_manifest_yq '.profiles | keys | .[]' 2>/dev/null || true)

  if [[ ! -d "${OPS_PROJECT_STATE_DIR}" ]]; then
    _warn ".ops.project/ state directory not found (run './ops.sh setup --apply')"
  fi
  debug "Pass 5: overrides checks complete"
}

# ── Run all passes ────────────────────────────────────────────────────────────
ops_section "ops experimental validate"
ops_info "Manifest: ${OPS_MANIFEST}"
printf '\n'

_pass1_syntax
_pass2_structural
_pass3_semantic
_pass4_filesystem
_pass5_overrides

# ── Print diagnostics ─────────────────────────────────────────────────────────
printf '\n'

if [[ ${#_ERRORS[@]} -gt 0 ]]; then
  _print_diag "ERROR" "${OPS_RED}"   "${_ERRORS[@]+"${_ERRORS[@]}"}"
fi
if [[ ${#_WARNINGS[@]} -gt 0 ]]; then
  _print_diag "WARN " "${OPS_YELLOW}" "${_WARNINGS[@]+"${_WARNINGS[@]}"}"
fi
if [[ ${#_HINTS[@]} -gt 0 ]]; then
  _print_diag "HINT " "${OPS_DIM}"   "${_HINTS[@]+"${_HINTS[@]}"}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf '\n'
_n_err="${#_ERRORS[@]}"
_n_warn="${#_WARNINGS[@]}"
_n_hint="${#_HINTS[@]}"

if [[ "${OPS_PLAIN}" == "true" ]]; then
  printf 'Validation: %d errors  %d warnings  %d hints\n' \
    "${_n_err}" "${_n_warn}" "${_n_hint}"
else
  printf '%s' "${OPS_BOLD}"
  printf 'Validation: %s%d errors%s  %s%d warnings%s  %s%d hints%s\n' \
    "${OPS_RED}"    "${_n_err}"  "${OPS_NC}${OPS_BOLD}" \
    "${OPS_YELLOW}" "${_n_warn}" "${OPS_NC}${OPS_BOLD}" \
    "${OPS_DIM}"    "${_n_hint}" "${OPS_NC}"
fi

if (( _n_err > 0 )); then
  exit 1
fi
exit 0
