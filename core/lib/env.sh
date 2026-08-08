#!/usr/bin/env bash
# .ops-core/lib/env.sh — Hierarchical environment broker (Phase 1.5+).
#
# Layer precedence (lowest → highest):
#   1. Process environment  (subshell inheritance — implicit)
#   2. project.global_env_files  (declaration order)
#   3. services.<id>.env_files   (declaration order)
#   4. Action-scoped env_files   (reserved for Phase 3)
#   5. CLI --env KEY=VALUE        (reserved for Phase 3)
#
# Isolation: env_assemble_context() populates OPS_ENV_CONTEXT / OPS_ENV_PROVENANCE.
# env_exec() runs a command in a subshell with those keys injected via `env`.
# No export into the calling shell — sequential service runs cannot bleed.
#
# Requires: init.sh, logger.sh, manifest.sh (sourced first)

set -euo pipefail
if [[ "${_OPS_CORE_ENV_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_ENV_LOADED=1

# ============================================================================
# GLOBAL CONTEXT ARRAYS
# Populated by env_assemble_context(); cleared at the start of each call.
# ============================================================================
declare -A OPS_ENV_CONTEXT=()       # KEY → value (from file layers)
declare -A OPS_ENV_PROVENANCE=()    # KEY → "layer:source" label

# ============================================================================
# SENSITIVE KEY PATTERNS — values matching these are masked in output
# ============================================================================
_OPS_SENSITIVE_PATTERNS=(
  '*_SECRET' '*_TOKEN' '*_PASSWORD' '*_PASSWD' '*_PASS'
  '*_KEY' '*_APIKEY' '*_API_KEY' '*_KEY_ID' '*_ACCESS_KEY_ID' '*_PRIVATE*'
  'SECRET_*' 'TOKEN_*' 'PASSWORD_*'
)

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

# Return 0 if KEY matches any sensitive pattern.
_env_is_sensitive() {
  local key="${1:?}"
  local pat
  for pat in "${_OPS_SENSITIVE_PATTERNS[@]}"; do
    # shellcheck disable=SC2254
    case "${key}" in ${pat}) return 0 ;; esac
  done
  return 1
}

# Return masked value if key is sensitive, original value otherwise.
_env_mask_value() {
  local key="$1" value="$2"
  _env_is_sensitive "${key}" && printf '***' || printf '%s' "${value}"
}

# Return 0 if this file should be skipped under CI policy.
# Skips files matching local-only naming patterns.
_env_should_skip_in_ci() {
  local file="$1" ci_mode="$2"
  [[ "${ci_mode}" != "true" ]] && return 1
  local base
  base="$(basename "${file}")"
  case "${base}" in
    *.local|.env.local|*.local.env|*.local.*) return 0 ;;
  esac
  return 1
}

# Parse a .env file into OPS_ENV_CONTEXT / OPS_ENV_PROVENANCE.
# Handles: comments, empty lines, export prefix, double/single quotes, CRLF.
_env_load_file() {
  local file="$1" label="$2"
  [[ ! -f "${file}" ]] && return 0
  [[ ! -r "${file}" ]] && { warn "_env_load_file: not readable: ${file}"; return 0; }

  local line key value
  while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "${line}" =~ ^[[:space:]]*$ ]]  && continue
    [[ "${line}" =~ ^[[:space:]]*#  ]] && continue
    # Strip 'export ' prefix
    line="${line#export }"
    # Must contain '='
    [[ "${line}" != *=* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    # Validate key
    [[ ! "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && continue
    # Strip surrounding double or single quotes
    if [[ "${value}" == \"*\" ]]; then
      value="${value#\"}"; value="${value%\"}"
    elif [[ "${value}" == \'*\' ]]; then
      value="${value#\'}"; value="${value%\'}"
    fi
    OPS_ENV_CONTEXT["${key}"]="${value}"
    OPS_ENV_PROVENANCE["${key}"]="${label}"
  done < <(sed 's/\r$//' "${file}")

  debug "_env_load_file: loaded from '${label}'"
}

# Assert a path (file or dir) is within the project root. Fails closed.
_env_assert_within_root() {
  local path="$1"
  case "${path}" in
    "${OPS_PROJECT_ROOT}"/*|"${OPS_PROJECT_ROOT}") return 0 ;;
    *) die "Path traversal denied: '${path}' is outside project root '${OPS_PROJECT_ROOT}'" ;;
  esac
}

# Assemble layered env context for a service.
# Populates OPS_ENV_CONTEXT and OPS_ENV_PROVENANCE (clears previous values).
# Flags: --ci-mode  (force CI behaviour regardless of OPS_CI var)
#
# Usage: env_assemble_context <service-id> [--ci-mode]
env_assemble_context() {
  local service_id="${1:?env_assemble_context: service id required}"
  shift

  # Determine CI mode
  local ci_mode="${OPS_CI:-false}"
  [[ "${ci_mode}" == "1" ]] && ci_mode=true
  local arg
  for arg in "$@"; do
    [[ "${arg}" == "--ci-mode" ]] && ci_mode=true
  done

  # Clear previous context
  OPS_ENV_CONTEXT=()
  OPS_ENV_PROVENANCE=()

  # Effective env_policy for this service
  local svc_policy
  svc_policy="$(project_get_service_field "${service_id}" env_policy 2>/dev/null || true)"
  [[ -z "${svc_policy}" || "${svc_policy}" == "null" ]] && svc_policy="dev_file"

  # ci_system policy → skip all file layers
  if [[ "${ci_mode}" == "true" && "${svc_policy}" == "ci_system" ]]; then
    debug "env_assemble_context: ci_system — skipping file layers for '${service_id}'"
    return 0
  fi

  # Layer 2: project.global_env_files
  local gef
  while IFS= read -r gef; do
    [[ -z "${gef}" || "${gef}" == "null" ]] && continue
    local abs_gef="${OPS_PROJECT_ROOT}/${gef}"
    if _env_should_skip_in_ci "${abs_gef}" "${ci_mode}"; then
      debug "env: CI skip (local-only): ${gef}"; continue
    fi
    if [[ ! -f "${abs_gef}" ]]; then
      warn "env: global env file not found: ${gef} (skipping)"; continue
    fi
    require_within_root "$(dirname "${abs_gef}")"
    _env_load_file "${abs_gef}" "global:${gef}"
  done < <(project_global_env_files)

  # Layer 3: service.env_files
  local ef
  while IFS= read -r ef; do
    [[ -z "${ef}" || "${ef}" == "null" ]] && continue
    local abs_ef="${OPS_PROJECT_ROOT}/${ef}"
    if _env_should_skip_in_ci "${abs_ef}" "${ci_mode}"; then
      debug "env: CI skip (local-only): ${ef}"; continue
    fi
    if [[ ! -f "${abs_ef}" ]]; then
      warn "env: service env file not found: ${ef} (skipping)"; continue
    fi
    _env_assert_within_root "${abs_ef}"
    _env_load_file "${abs_ef}" "service:${ef}"
  done < <(project_get_service_list_field "${service_id}" env_files 2>/dev/null || true)

  # Layers 4 & 5 reserved for Phase 3 (action-scoped + CLI --env overrides)

  debug "env_assemble_context: ${#OPS_ENV_CONTEXT[@]} keys loaded for '${service_id}'"
}

# Execute a command inside a fully isolated env context for a service.
# Runs in a subshell — no leakage into the caller's shell.
# The subshell inherits the process env (layer 1) and the assembled file-layer
# context is injected on top via `env KEY=val ...`.
#
# Usage: env_exec <service-id> [--ci-mode] -- <command> [args...]
env_exec() {
  local service_id="${1:?env_exec: service id required}"
  shift
  local ci_flag=""
  while [[ $# -gt 0 && "${1}" != "--" ]]; do
    [[ "${1}" == "--ci-mode" ]] && ci_flag="--ci-mode"
    shift
  done
  [[ "${1:-}" == "--" ]] && shift

  env_assemble_context "${service_id}" ${ci_flag}

  local svc_path
  svc_path="$(project_get_service_field "${service_id}" path)"
  local abs_path="${OPS_PROJECT_ROOT}/${svc_path}"
  require_within_root "${abs_path}"

  # Build env override list from assembled context
  local env_overrides=()
  local k
  for k in "${!OPS_ENV_CONTEXT[@]}"; do
    env_overrides+=("${k}=${OPS_ENV_CONTEXT[${k}]}")
  done

  debug "env_exec: subshell for '${service_id}' — ${#env_overrides[@]} overrides, cwd=${abs_path}"

  (
    if [[ -n "${OPS_CONDA_ENV:-}" ]]; then
      local conda_base="${OPS_CONDA_BASE:-}"
      if [[ -z "${conda_base}" ]] && command -v conda >/dev/null 2>&1; then
        conda_base="$(conda info --base 2>/dev/null || true)"
      fi
      if [[ -z "${conda_base}" && -n "${HOME:-}" ]]; then
        for candidate in "${HOME}/miniconda3" "${HOME}/anaconda3" "/home/dev/miniconda3" "/home/dev/anaconda3"; do
          [[ -f "${candidate}/etc/profile.d/conda.sh" ]] && { conda_base="${candidate}"; break; }
        done
      fi
      if [[ -n "${conda_base}" && -f "${conda_base}/etc/profile.d/conda.sh" ]]; then
        # shellcheck source=/dev/null
        source "${conda_base}/etc/profile.d/conda.sh"
        conda activate "${OPS_CONDA_ENV}"
      else
        die "Conda environment requested via OPS_CONDA_ENV but conda shell integration is not available." 3
      fi
    fi
    cd "${abs_path}" || exit 1
    exec env "${env_overrides[@]}" "$@"
  )
}

# Print a provenance table for the assembled env context of a service.
# Sensitive values are masked unless --unmask is passed.
#
# Usage: env_show_context <service-id> [--unmask] [--ci-mode]
env_show_context() {
  local service_id="${1:?env_show_context: service id required}"
  shift
  local unmask=false ci_flag=""
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --unmask)   unmask=true ;;
      --ci-mode)  ci_flag="--ci-mode" ;;
    esac
  done

  env_assemble_context "${service_id}" ${ci_flag}

  local n="${#OPS_ENV_CONTEXT[@]}"
  if [[ "${n}" -eq 0 ]]; then
    ops_info "  No env keys loaded from file layers for '${service_id}'."
    ops_info "  Add env_files to the service or global_env_files to .ops.project/config/project.json"
    return 0
  fi

  # Header
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    printf '%-32s  %-24s  %s\n' "KEY" "VALUE" "SOURCE"
    printf '%-32s  %-24s  %s\n' "---" "-----" "------"
  else
    printf '%s%-32s  %-24s  %s%s\n' \
      "${OPS_BOLD}" "KEY" "VALUE" "SOURCE" "${OPS_NC}"
    printf '%-32s  %-24s  %s\n' "---" "-----" "------"
  fi

  # Rows (sorted by key)
  local k display_val src
  while IFS= read -r k; do
    [[ -z "${k}" ]] && continue
    display_val="$(_env_mask_value "${k}" "${OPS_ENV_CONTEXT[${k}]}")"
    [[ "${unmask}" == "true" ]] && display_val="${OPS_ENV_CONTEXT[${k}]}"
    src="${OPS_ENV_PROVENANCE[${k}]:-unknown}"
    printf '%-32s  %-24s  %s\n' "${k}" "${display_val}" "${src}"
  done < <(printf '%s\n' "${!OPS_ENV_CONTEXT[@]}" | sort)
}

# Diagnose missing env files and policy issues for a service.
# Returns 1 if any errors found.
#
# Usage: env_doctor_check <service-id>
env_doctor_check() {
  local service_id="${1:?env_doctor_check: service id required}"
  local errors=0 warnings=0

  # Global env files
  local gef
  while IFS= read -r gef; do
    [[ -z "${gef}" || "${gef}" == "null" ]] && continue
    local abs="${OPS_PROJECT_ROOT}/${gef}"
    if [[ ! -f "${abs}" ]]; then
      ops_error "  global_env_files — not found: '${gef}'"
      errors=$((errors+1))
    elif [[ ! -r "${abs}" ]]; then
      ops_error "  global_env_files — not readable: '${gef}'"
      errors=$((errors+1))
    else
      ops_ok    "  global_env_files — ok: '${gef}'"
    fi
  done < <(project_global_env_files)

  # Service env_files
  local ef
  while IFS= read -r ef; do
    [[ -z "${ef}" || "${ef}" == "null" ]] && continue
    local abs="${OPS_PROJECT_ROOT}/${ef}"
    if [[ ! -f "${abs}" ]]; then
      ops_error "  env_files — not found: '${ef}'"
      errors=$((errors+1))
    elif [[ ! -r "${abs}" ]]; then
      ops_error "  env_files — not readable: '${ef}'"
      errors=$((errors+1))
    else
      ops_ok    "  env_files — ok: '${ef}'"
    fi
  done < <(project_get_service_list_field "${service_id}" env_files 2>/dev/null || true)

  # Policy info
  local policy
  policy="$(project_get_service_field "${service_id}" env_policy 2>/dev/null || true)"
  [[ -z "${policy}" || "${policy}" == "null" ]] && policy="dev_file"
  ops_info "  env_policy: ${policy}"

  # CI warning
  if [[ "${OPS_CI:-false}" == "true" && "${policy}" == "dev_file" ]]; then
    ops_warn "  CI mode active but env_policy=dev_file — local files will be loaded"
    warnings=$((warnings+1))
  fi

  # No files declared at any layer (and policy requires them)
  if [[ "${policy}" == "dev_file" ]]; then
    local global_count svc_count
    global_count="$(project_global_env_file_count)"
    svc_count="$(project_get_service_json_field "${service_id}" env_files '[]' | jq -r 'length' 2>/dev/null || echo 0)"
    if [[ "${global_count}" == "0" && ("${svc_count}" == "0" || -z "${svc_count}") ]]; then
      ops_warn "  No env files declared at any layer (env_policy=dev_file but no files configured)"
      warnings=$((warnings+1))
    fi
  fi

  printf '\n'
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    printf 'env doctor [%s]: %d errors  %d warnings\n' "${service_id}" "${errors}" "${warnings}"
  else
    printf '%senv doctor [%s]:%s %s%d errors%s  %s%d warnings%s\n' \
      "${OPS_BOLD}" "${service_id}" "${OPS_NC}" \
      "${OPS_RED}"    "${errors}"   "${OPS_NC}" \
      "${OPS_YELLOW}" "${warnings}" "${OPS_NC}"
  fi

  return "${errors}"
}
