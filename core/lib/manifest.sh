#!/usr/bin/env bash
# .ops-core/lib/manifest.sh — config-first project access layer.
#
# Requires: jq for project config; yq (mikefarah v4+) for YAML fallback;
# init.sh must be sourced first. Dependencies are loaded lazily.

# Compatibility boundary:
# - project_* functions own config-first runtime reads.
# - manifest_* names are compatibility wrappers for legacy callers.
# - require_manifest is for explicit YAML compatibility paths only.
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

_manifest_yq_json() {
  require_bins yq
  local expr="${1:?_manifest_yq_json: yq expression required}"
  yq e -o=json -I=0 "${expr}" "${OPS_MANIFEST}"
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

project_config_exists() {
  project_config_services_exists
}

# Abort with a helpful message if .ops.yaml does not exist.
require_manifest() {
  if ! manifest_exists; then
    die "No manifest found at '${OPS_MANIFEST}'.
  Generate one with:  ops setup --apply
  Export config:      ops setup export-yaml
  Then validate:      ops validate --plain" 2
  fi
}

# Prepare .ops.yaml as a compatibility validation source.
manifest_prepare_validation_source() {
  if manifest_exists; then
    MANIFEST_VALIDATE_SOURCE="${OPS_MANIFEST}"
    MANIFEST_VALIDATE_TEMP=false
    export MANIFEST_VALIDATE_SOURCE MANIFEST_VALIDATE_TEMP
    return 0
  fi
  die "No .ops.yaml compatibility manifest found at '${OPS_MANIFEST}'." 2
}

manifest_cleanup_validation_source() {
  if [[ "${MANIFEST_VALIDATE_TEMP:-false}" == "true" ]]; then
    rm -f "${MANIFEST_VALIDATE_SOURCE:-}"
  fi
}

# Require project ops state: .ops.project/config/services.json or .ops.yaml.
project_require_config_or_yaml() {
  if project_config_services_exists; then
    return 0
  fi
  require_manifest
}

# Legacy compatibility wrapper.
require_manifest_or_config() {
  project_require_config_or_yaml
}

# Return 0 if a service with the given ID is declared in project config.
project_service_exists() {
  local id="${1:?project_service_exists: service id required}"
  local result=""
  if project_config_services_exists; then
    require_bins jq
    result="$(jq -r --arg id "${id}" '.services[]? | select(.id == $id) | .id' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || true)"
    [[ -n "${result}" ]]
    return $?
  fi
  require_manifest
  result="$(_manifest_yq ".services[] | select(.id == \"${id}\") | .id")"
  [[ -n "${result}" ]]
}

# Legacy compatibility wrapper.
manifest_service_exists() {
  project_service_exists "$@"
}

# ============================================================================
# PROJECT-LEVEL ACCESSORS
# ============================================================================

# Get a project-level field value.
# Usage: project_get_field name
# Usage: project_get_field global_env_files
project_get_field() {
  local field="${1:?project_get_field: field required}"
  if [[ -f "${OPS_PROJECT_CONFIG_PROJECT_FILE}" ]]; then
    require_bins jq
    jq -r --arg field "${field}" '
      def getpathstr($path):
        getpath($path | split(".") | map(if test("^[0-9]+$") then tonumber else . end));
      getpathstr($field) // ""
    ' "${OPS_PROJECT_CONFIG_PROJECT_FILE}" 2>/dev/null || true
    return 0
  fi
  require_manifest
  _manifest_yq_or_empty ".project.${field}"
}

# Legacy compatibility wrapper.
manifest_get_project_field() {
  project_get_field "$@"
}

# Print project global env files, one item per line, preferring .ops.project/config.
project_global_env_files() {
  if [[ -f "${OPS_PROJECT_CONFIG_PROJECT_FILE}" ]]; then
    require_bins jq
    jq -r '.global_env_files[]?' "${OPS_PROJECT_CONFIG_PROJECT_FILE}" 2>/dev/null || true
    return 0
  fi
  manifest_get_field '.project.global_env_files[]?' 2>/dev/null || true
}

project_global_env_file_count() {
  if [[ -f "${OPS_PROJECT_CONFIG_PROJECT_FILE}" ]]; then
    require_bins jq
    jq -r '(.global_env_files // []) | length' "${OPS_PROJECT_CONFIG_PROJECT_FILE}" 2>/dev/null || printf '0'
    return 0
  fi
  manifest_get_field '.project.global_env_files | length' 2>/dev/null || printf '0'
}

# ============================================================================
# SERVICE LISTING
# ============================================================================

# Print all declared service IDs, one per line.
project_list_services() {
  if project_config_services_exists; then
    require_bins jq
    jq -r '.services[]?.id' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || true
    return 0
  fi
  require_manifest
  _manifest_yq '.services[].id'
}

# Legacy compatibility wrapper.
manifest_list_services() {
  project_list_services "$@"
}

# ============================================================================
# SERVICE FIELD ACCESSORS
# ============================================================================

# Get a scalar field from a specific service.
# Usage: project_get_service_field backend stack
# Usage: project_get_service_field backend actions.start
project_get_service_field() {
  local id="${1:?project_get_service_field: service id required}"
  local field="${2:?project_get_service_field: field path required}"
  local value=""
  if project_config_services_exists; then
    require_bins jq
    value="$(jq -r --arg id "${id}" --arg field "${field}" '
      def getpathstr($path):
        getpath($path | split(".") | map(if test("^[0-9]+$") then tonumber else . end));
      (.services[]? | select(.id == $id) | getpathstr($field)) // ""
    ' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || true)"
    if jq -e --arg id "${id}" '.services[]? | select(.id == $id)' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" >/dev/null 2>&1; then
      [[ "${value}" == "null" ]] && value=""
      printf '%s' "${value}"
      return 0
    fi
  fi
  require_manifest
  _manifest_yq_or_empty ".services[] | select(.id == \"${id}\") | .${field}"
}

# Legacy compatibility wrapper.
manifest_get_service_field() {
  project_get_service_field "$@"
}

# Get a list field from a specific service, one item per line.
# Usage: project_get_service_list_field backend depends_on
# Usage: project_get_service_list_field backend env_files
project_get_service_list_field() {
  local id="${1:?project_get_service_list_field: service id required}"
  local field="${2:?project_get_service_list_field: field path required}"
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

# Legacy compatibility wrapper.
manifest_get_service_list_field() {
  project_get_service_list_field "$@"
}

# Get any service field as compact JSON. This keeps structured config/YAML
# compatibility handling inside the project access layer.
# Usage: project_get_service_json_field backend build.outputs '[]'
project_get_service_json_field() {
  local id="${1:?project_get_service_json_field: service id required}"
  local field="${2:?project_get_service_json_field: field path required}"
  local default_json="${3:-null}"
  if project_config_services_exists; then
    require_bins jq
    jq -c --arg id "${id}" --arg field "${field}" --argjson default "${default_json}" '
      def getpathstr($path):
        getpath($path | split(".") | map(if test("^[0-9]+$") then tonumber else . end));
      (.services[]? | select(.id == $id) | getpathstr($field)) // $default
    ' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || printf '%s' "${default_json}"
    return 0
  fi
  require_manifest
  _manifest_yq_json ".services[] | select(.id == \"${id}\") | .${field} // ${default_json}" \
    2>/dev/null || printf '%s' "${default_json}"
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
