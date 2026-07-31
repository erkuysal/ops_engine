#!/usr/bin/env bash
# Machine-global named deployment profile resolution.

set -euo pipefail
if [[ "${_OPS_GLOBAL_PROFILES_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_GLOBAL_PROFILES_LOADED=1

OPS_GLOBAL_CONFIG_HOME="${OPS_GLOBAL_CONFIG_HOME:-${XDG_CONFIG_HOME:-${HOME}/.config}/ops}"
OPS_GLOBAL_PROFILES_DIR="${OPS_GLOBAL_PROFILES_DIR:-${OPS_GLOBAL_CONFIG_HOME}/profiles}"
export OPS_GLOBAL_CONFIG_HOME OPS_GLOBAL_PROFILES_DIR

global_profile_validate_id() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

global_profile_file() {
  local id="${1:?global_profile_file: profile id required}"
  global_profile_validate_id "${id}" || die "Invalid global profile id: ${id}" 2
  printf '%s/%s.json' "${OPS_GLOBAL_PROFILES_DIR}" "${id}"
}

global_profile_exists() {
  [[ -f "$(global_profile_file "$1")" ]]
}

global_profile_list() {
  local file
  [[ -d "${OPS_GLOBAL_PROFILES_DIR}" ]] || return 0
  for file in "${OPS_GLOBAL_PROFILES_DIR}"/*.json; do
    [[ -f "${file}" ]] || continue
    basename "${file}" .json
  done | LC_ALL=C sort
}

global_profile_json() {
  local id="$1" file
  file="$(global_profile_file "${id}")"
  [[ -f "${file}" ]] || die "Global profile not found: ${id}. Run: ops global list" 2
  jq -e --arg id "${id}" '
    .version == 1 and (.id == $id) and
    (.deploy | type == "object") and (.docker | type == "object")
  ' "${file}" >/dev/null || die "Invalid global profile: ${file}" 2
  cat "${file}"
}

global_profile_ref_from_ci_json() {
  jq -r '.global_profile // ""' <<< "$1"
}

global_profile_resolve_ci_json() {
  local project_json="$1" ref profile_json project_name
  ref="$(global_profile_ref_from_ci_json "${project_json}")"
  [[ -n "${ref}" ]] || { printf '%s' "${project_json}"; return 0; }
  profile_json="$(global_profile_json "${ref}")"
  project_name="$(jq -r '.project.name // "project"' <<< "${project_json}")"

  jq -n \
    --arg ref "${ref}" \
    --arg project "${project_name}" \
    --argjson global "${profile_json}" \
    --argjson local "${project_json}" '
      def compact:
        if type == "object" then
          with_entries(.value |= compact | select(.value != null and .value != ""))
        else . end;
      ($global | {deploy: (.deploy // {}), docker: (.docker // {})}) as $base
      | ($base * ($local | compact))
      | .global_profile = $ref
      | if ((.deploy.path // "") == "") and (($global.deploy.path_template // "") != "") then
          .deploy.path = ($global.deploy.path_template | gsub("\\{project\\}"; $project))
        else . end
      | del(.deploy.path_template)
    '
}

global_profile_resolve_ci_file() {
  local file="$1"
  [[ -f "${file}" ]] || return 1
  global_profile_resolve_ci_json "$(cat "${file}")"
}
