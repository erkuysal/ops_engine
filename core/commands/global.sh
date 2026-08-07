#!/usr/bin/env bash
# Manage machine-global deployment profiles and project profile references.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/global_profiles.sh"

SUBCMD="${1:-list}"
case "${SUBCMD}" in
  setup|list|show|use|current|doctor|help|--help|-h) shift || true ;;
  *) die "Unknown global subcommand: ${SUBCMD}" 2 ;;
esac

PROFILE_ID=""
APPLY=false
INTERACTIVE=false
JSON=false
HOST=""
USER_NAME=""
PATH_TEMPLATE=""
PROJECT_PATH=""
SSH_KEY_PATH=""
DOCKER_REGISTRY=""
DOCKER_NAMESPACE=""
DOCKER_USER=""

if [[ $# -gt 0 && "${1}" != --* ]]; then PROFILE_ID="$1"; shift; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true ;;
    --interactive) INTERACTIVE=true ;;
    --json) JSON=true ;;
    --host=*) HOST="${1#*=}" ;;
    --user=*) USER_NAME="${1#*=}" ;;
    --path-template=*) PATH_TEMPLATE="${1#*=}" ;;
    --project-path=*) PROJECT_PATH="${1#*=}" ;;
    --ssh-key=*) SSH_KEY_PATH="${1#*=}" ;;
    --docker-registry=*) DOCKER_REGISTRY="${1#*=}" ;;
    --docker-namespace=*) DOCKER_NAMESPACE="${1#*=}" ;;
    --docker-user=*) DOCKER_USER="${1#*=}" ;;
    --help|-h) SUBCMD=help ;;
    *) die "Unknown global flag: $1" 2 ;;
  esac
  shift
done

_usage_global() {
  cat <<EOF
Usage: ops global setup NAME [--interactive] [--apply]
       ops global setup NAME --host=HOST --user=USER --path-template=/srv/{project} --ssh-key=PATH --docker-registry=REGISTRY --docker-namespace=NAME --docker-user=USER --apply
       ops global list [--json]
       ops global show NAME [--json]
       ops global use NAME [--project-path=PATH] [--apply]
       ops global current [--json]
       ops global doctor [NAME]

Profiles live under ${XDG_CONFIG_HOME:-~/.config}/ops/profiles. Projects store
only a global_profile reference and optional overrides in
.ops.project/config/ci.json. Secret values are not stored in profile JSON.
EOF
}

_prompt_global() {
  local label="$1" default="${2:-}" value
  if [[ -n "${default}" ]]; then printf '%s [%s]: ' "${label}" "${default}" >&2; else printf '%s: ' "${label}" >&2; fi
  IFS= read -r value || value=""
  printf '%s' "${value:-${default}}"
}

_profile_value() {
  local expr="$1" default="${2:-}"
  if [[ -n "${PROFILE_ID}" ]] && global_profile_exists "${PROFILE_ID}"; then
    jq -r "${expr} // \"\"" "$(global_profile_file "${PROFILE_ID}")" 2>/dev/null | sed -n '1p'
  else
    printf '%s' "${default}"
  fi
}

_setup_profile() {
  [[ -n "${PROFILE_ID}" ]] || die "Global profile name required." 2
  global_profile_validate_id "${PROFILE_ID}" || die "Invalid global profile id: ${PROFILE_ID}" 2
  [[ -n "${HOST}" ]] || HOST="$(_profile_value '.deploy.host')"
  [[ -n "${USER_NAME}" ]] || USER_NAME="$(_profile_value '.deploy.user')"
  [[ -n "${PATH_TEMPLATE}" ]] || PATH_TEMPLATE="$(_profile_value '.deploy.path_template' '/srv/{project}')"
  [[ -n "${SSH_KEY_PATH}" ]] || SSH_KEY_PATH="$(_profile_value '.deploy.ssh_key_path')"
  [[ -n "${DOCKER_REGISTRY}" ]] || DOCKER_REGISTRY="$(_profile_value '.docker.registry' 'docker.io')"
  [[ -n "${DOCKER_NAMESPACE}" ]] || DOCKER_NAMESPACE="$(_profile_value '.docker.namespace')"
  [[ -n "${DOCKER_USER}" ]] || DOCKER_USER="$(_profile_value '.docker.username')"

  if [[ "${INTERACTIVE}" == "true" ]]; then
    HOST="$(_prompt_global 'VPS host' "${HOST}")"
    USER_NAME="$(_prompt_global 'SSH/deploy user' "${USER_NAME}")"
    PATH_TEMPLATE="$(_prompt_global 'Deploy path template ({project} is replaced)' "${PATH_TEMPLATE}")"
    SSH_KEY_PATH="$(_prompt_global 'SSH private key path' "${SSH_KEY_PATH}")"
    DOCKER_REGISTRY="$(_prompt_global 'Docker registry' "${DOCKER_REGISTRY}")"
    DOCKER_NAMESPACE="$(_prompt_global 'Docker namespace/user' "${DOCKER_NAMESPACE}")"
    DOCKER_USER="$(_prompt_global 'Docker login username (optional)' "${DOCKER_USER:-${DOCKER_NAMESPACE}}")"
  fi
  [[ -n "${DOCKER_USER}" ]] || DOCKER_USER="${DOCKER_NAMESPACE}"

  local profile_json file
  profile_json="$(jq -n \
    --arg id "${PROFILE_ID}" --arg generated_at "$(ops_timestamp)" \
    --arg host "${HOST}" --arg user "${USER_NAME}" --arg path_template "${PATH_TEMPLATE}" \
    --arg ssh_key_path "${SSH_KEY_PATH}" --arg registry "${DOCKER_REGISTRY}" --arg namespace "${DOCKER_NAMESPACE}" --arg docker_user "${DOCKER_USER}" '
    {
      version: 1, id: $id, updated_at: $generated_at,
      deploy: {host: $host, user: $user, path_template: $path_template, ssh_key_path: $ssh_key_path},
      docker: {
        registry: $registry, namespace: $namespace, username: $docker_user,
        credentials: {source: "docker-credential-store", username_env: "DOCKER_USERNAME", password_env: "DOCKER_PASSWORD"}
      }
    }')"
  if [[ "${JSON}" == "true" ]]; then printf '%s\n' "${profile_json}"; return 0; fi
  jq -r '"Profile: " + .id, "SSH: " + (.deploy.user // "") + "@" + (.deploy.host // ""), "Deploy path: " + (.deploy.path_template // ""), "Docker: " + (.docker.registry // "") + "/" + (.docker.namespace // "")' <<< "${profile_json}"
  if [[ "${APPLY}" == "true" ]]; then
    ensure_dir "${OPS_GLOBAL_PROFILES_DIR}"
    chmod 700 "${OPS_GLOBAL_CONFIG_HOME}" "${OPS_GLOBAL_PROFILES_DIR}" 2>/dev/null || true
    file="$(global_profile_file "${PROFILE_ID}")"
    local tmp
    tmp="$(mktemp "${OPS_GLOBAL_PROFILES_DIR}/.${PROFILE_ID}.XXXXXX")"
    printf '%s\n' "${profile_json}" > "${tmp}"
    chmod 600 "${tmp}" 2>/dev/null || true
    mv "${tmp}" "${file}"
    ops_ok "Wrote global profile: ${file}"
  else
    ops_info "Preview only. Use --apply to write the profile."
  fi
}

_list_profiles() {
  local profiles='[]' id
  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    profiles="$(jq -c --arg id "${id}" '. + [$id]' <<< "${profiles}")"
  done < <(global_profile_list)
  if [[ "${JSON}" == "true" ]]; then printf '%s\n' "${profiles}"; else
    printf 'Global profiles (%s):\n' "${OPS_GLOBAL_PROFILES_DIR}"
    if [[ "$(jq 'length' <<< "${profiles}")" -eq 0 ]]; then printf '  <none>\n'; else jq -r '.[] | "  " + .' <<< "${profiles}"; fi
  fi
}

_show_profile() {
  [[ -n "${PROFILE_ID}" ]] || die "Global profile name required." 2
  local profile_json; profile_json="$(global_profile_json "${PROFILE_ID}")"
  if [[ "${JSON}" == "true" ]]; then printf '%s\n' "${profile_json}"; else jq . <<< "${profile_json}"; fi
}

_project_ci_file() { printf '%s/ci.json' "${OPS_PROJECT_CONFIG_DIR}"; }

_use_profile() {
  [[ -n "${PROFILE_ID}" ]] || die "Global profile name required." 2
  global_profile_json "${PROFILE_ID}" >/dev/null
  local file config_json resolved
  file="$(_project_ci_file)"
  if [[ -f "${file}" ]]; then config_json="$(cat "${file}")"; else
    config_json="$(jq -n --arg name "$(basename "${OPS_PROJECT_ROOT}")" '{version:1,project:{name:$name},docker:{image_prefix:$name},deploy:{},secrets:{local_env_file:".ops.project/secrets/ci.env"}}')"
  fi
  config_json="$(jq --arg ref "${PROFILE_ID}" --arg path "${PROJECT_PATH}" --arg generated_at "$(ops_timestamp)" '
    .global_profile = $ref
    | .generated_at = $generated_at
    | .deploy = (.deploy // {})
    | .deploy.host = "" | .deploy.user = "" | .deploy.ssh_key_path = ""
    | if $path != "" then .deploy.path = $path else .deploy.path = "" end
    | .docker = (.docker // {})
    | .docker.registry = "" | .docker.namespace = ""
  ' <<< "${config_json}")"
  resolved="$(global_profile_resolve_ci_json "${config_json}")"
  printf 'Project profile: %s\n' "${PROFILE_ID}"
  jq -r '"Resolved SSH: " + (.deploy.user // "") + "@" + (.deploy.host // ""), "Resolved path: " + (.deploy.path // ""), "Resolved Docker namespace: " + (.docker.namespace // "")' <<< "${resolved}"
  if [[ "${APPLY}" == "true" ]]; then
    ensure_dir "${OPS_PROJECT_CONFIG_DIR}"
    printf '%s\n' "${config_json}" > "${file}"
    ops_ok "Updated project profile reference: ${file#${OPS_PROJECT_ROOT}/}"
  else ops_info "Preview only. Use --apply to select this profile."; fi
}

_current_profile() {
  local file ref raw resolved
  file="$(_project_ci_file)"
  [[ -f "${file}" ]] || die "Project CI config not found. Run: ops ci setup --apply" 2
  raw="$(cat "${file}")"; ref="$(global_profile_ref_from_ci_json "${raw}")"
  [[ -n "${ref}" ]] || die "Project has no global profile. Run: ops global use NAME --apply" 2
  resolved="$(global_profile_resolve_ci_json "${raw}")"
  if [[ "${JSON}" == "true" ]]; then printf '%s\n' "${resolved}"; else
    printf 'Global profile: %s\n' "${ref}"
    jq -r '"SSH: " + (.deploy.user // "") + "@" + (.deploy.host // ""), "Deploy path: " + (.deploy.path // ""), "Docker: " + (.docker.registry // "") + "/" + (.docker.namespace // "")' <<< "${resolved}"
  fi
}

_doctor_profile() {
  [[ -n "${PROFILE_ID}" ]] || PROFILE_ID="$(jq -r '.global_profile // ""' "$(_project_ci_file)" 2>/dev/null || true)"
  [[ -n "${PROFILE_ID}" ]] || die "Select a profile name or configure the project reference." 2
  local profile_json key warn=0
  profile_json="$(global_profile_json "${PROFILE_ID}")"
  key="$(jq -r '.deploy.ssh_key_path // ""' <<< "${profile_json}")"; key="${key/#\~/${HOME}}"
  jq -e '.deploy.host != "" and .deploy.user != "" and .docker.registry != ""' <<< "${profile_json}" >/dev/null || { ops_warn "Profile has missing connection fields"; warn=$((warn+1)); }
  if [[ -n "${key}" && -f "${key}" ]]; then ops_ok "SSH key exists: ${key}"; else ops_warn "SSH key missing: ${key:-<unset>}"; warn=$((warn+1)); fi
  printf 'Global profile doctor: %d warnings\n' "${warn}"
}

case "${SUBCMD}" in
  setup) _setup_profile ;;
  list) _list_profiles ;;
  show) _show_profile ;;
  use) _use_profile ;;
  current) _current_profile ;;
  doctor) _doctor_profile ;;
  help|--help|-h) _usage_global ;;
esac
