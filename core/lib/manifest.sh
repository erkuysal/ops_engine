#!/usr/bin/env bash
# .ops-core/lib/manifest.sh — YAML manifest loader for .ops.yaml (Phase 1+).
#
# Requires: yq (mikefarah v4+), init.sh (sourced first)
# All functions that read the manifest call require_manifest first.
# yq is called lazily — install it before using validate/bootstrap.

set -euo pipefail
if [[ "${_OPS_CORE_MANIFEST_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_MANIFEST_LOADED=1

# ============================================================================
# KNOWN STACKS — single source of truth for validator + stack dispatch
# ============================================================================
OPS_KNOWN_STACKS=(django elixir-phoenix go node docker custom)
export OPS_KNOWN_STACKS

# Valid env_policy values
OPS_VALID_ENV_POLICIES=(dev_file ci_system mixed)
export OPS_VALID_ENV_POLICIES

# Valid env_materialization values
OPS_VALID_ENV_MATERIALIZATIONS=(none symlink generated_file)
export OPS_VALID_ENV_MATERIALIZATIONS

OPS_PROJECT_CONFIG_DIR="${OPS_PROJECT_CONFIG_DIR:-${OPS_PROJECT_ROOT}/.ops.project/config}"
OPS_PROJECT_CONFIG_SERVICES_FILE="${OPS_PROJECT_CONFIG_SERVICES_FILE:-${OPS_PROJECT_CONFIG_DIR}/services.json}"
OPS_PROJECT_CONFIG_PROJECT_FILE="${OPS_PROJECT_CONFIG_PROJECT_FILE:-${OPS_PROJECT_CONFIG_DIR}/project.json}"
export OPS_PROJECT_CONFIG_DIR OPS_PROJECT_CONFIG_SERVICES_FILE OPS_PROJECT_CONFIG_PROJECT_FILE

# ============================================================================
# INTERNAL: yq wrapper — all manifest reads go through here
# ============================================================================

# Run a yq expression against the manifest file.
# Usage: _manifest_yq '.services[].id'
_manifest_yq() {
  require_bins yq
  local expr="${1:?_manifest_yq: yq expression required}"
  yq e "${expr}" "${OPS_MANIFEST}"
}

# Run a yq expression and return empty string (not null literal) on missing keys.
# Usage: _manifest_yq_or_empty '.project.name'
_manifest_yq_or_empty() {
  local result
  result="$(_manifest_yq "${1} // \"\"")"
  printf '%s' "${result}"
}

# ============================================================================
# EXISTENCE CHECKS
# ============================================================================

# Return 0 if .ops.yaml exists.
manifest_exists() {
  [[ -f "${OPS_MANIFEST}" ]]
}

project_config_services_exists() {
  [[ -f "${OPS_PROJECT_CONFIG_SERVICES_FILE}" ]]
}

# Abort with a helpful message if .ops.yaml does not exist.
require_manifest() {
  if ! manifest_exists; then
    die "No manifest found at '${OPS_MANIFEST}'.
  Generate one with:  ./ops.sh experimental bootstrap
  Then validate:       ./ops.sh experimental validate" 2
  fi
}

# Return 0 if a service with the given ID is declared in the manifest.
manifest_service_exists() {
  local id="${1:?manifest_service_exists: service id required}"
  local result=""
  if project_config_services_exists; then
    require_bins jq
    result="$(jq -r --arg id "${id}" '.services[]? | select(.id == $id) | .id' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || true)"
  fi
  if [[ -z "${result}" ]]; then
    require_manifest
    result="$(_manifest_yq ".services[] | select(.id == \"${id}\") | .id")"
  fi
  [[ -n "${result}" ]]
}

# ============================================================================
# PROJECT-LEVEL ACCESSORS
# ============================================================================

# Get a project-level field value.
# Usage: manifest_get_project_field name
# Usage: manifest_get_project_field global_env_files
manifest_get_project_field() {
  local field="${1:?manifest_get_project_field: field required}"
  require_manifest
  _manifest_yq_or_empty ".project.${field}"
}

# ============================================================================
# SERVICE LISTING
# ============================================================================

# Print all declared service IDs, one per line.
manifest_list_services() {
  if project_config_services_exists; then
    require_bins jq
    jq -r '.services[]?.id' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || true
    return 0
  fi
  require_manifest
  _manifest_yq '.services[].id'
}

# ============================================================================
# SERVICE FIELD ACCESSORS
# ============================================================================

# Get a scalar field from a specific service.
# Usage: manifest_get_service_field backend stack
# Usage: manifest_get_service_field backend actions.start
manifest_get_service_field() {
  local id="${1:?manifest_get_service_field: service id required}"
  local field="${2:?manifest_get_service_field: field path required}"
  local value=""
  if project_config_services_exists; then
    require_bins jq
    value="$(jq -r --arg id "${id}" --arg field "${field}" '
      def getpathstr($path):
        getpath($path | split(".") | map(if test("^[0-9]+$") then tonumber else . end));
      (.services[]? | select(.id == $id) | getpathstr($field)) // ""
    ' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || true)"
    [[ -n "${value}" && "${value}" != "null" ]] && { printf '%s' "${value}"; return 0; }
  fi
  require_manifest
  _manifest_yq_or_empty ".services[] | select(.id == \"${id}\") | .${field}"
}

# Get a list field from a specific service, one item per line.
# Usage: manifest_get_service_list_field backend depends_on
# Usage: manifest_get_service_list_field backend env_files
manifest_get_service_list_field() {
  local id="${1:?manifest_get_service_list_field: service id required}"
  local field="${2:?manifest_get_service_list_field: field path required}"
  if project_config_services_exists; then
    require_bins jq
    jq -r --arg id "${id}" --arg field "${field}" '
      def getpathstr($path):
        getpath($path | split(".") | map(if test("^[0-9]+$") then tonumber else . end));
      .services[]?
      | select(.id == $id)
      | if ($field | endswith(".name")) then
          (getpathstr($field | sub("\\.name$"; "")) // [] | .[]?.name)
        else
          (getpathstr($field) // [] | .[]?)
        end
    ' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || true
    return 0
  fi
  require_manifest
  _manifest_yq ".services[] | select(.id == \"${id}\") | .${field}[]?" 2>/dev/null || true
}

# ============================================================================
# GENERIC ACCESSOR
# ============================================================================

# Evaluate an arbitrary yq expression against the manifest.
# Usage: manifest_get_field '.ci.env_policy'
manifest_get_field() {
  local expr="${1:?manifest_get_field: yq expression required}"
  require_manifest
  _manifest_yq "${expr}"
}
