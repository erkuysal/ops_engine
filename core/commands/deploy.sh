#!/usr/bin/env bash
# .ops/core/commands/deploy.sh - Native basic remote container deploy command.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unset OPS_PROJECT_CONFIG_DIR OPS_PROJECT_CONFIG_SERVICES_FILE OPS_PROJECT_CONFIG_PROJECT_FILE
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
unset OPS_PROJECT_CONFIG_SERVICES_FILE OPS_PROJECT_CONFIG_PROJECT_FILE
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/container_pipeline.sh"

SERVICE=""
COMPOSE_SERVICE=""
ALL=false
TAG=""
DRY_RUN=false
JSON=false
PULL_ONLY=false
NO_PULL=false
BUILD=false
NO_START=false
NON_INTERACTIVE=false

_usage_deploy() {
  cat <<'EOF'
Usage: ops deploy [SERVICE] [--service=ID|--all] [--compose-service=NAME] [--tag=TAG] [--pull-only] [--no-pull] [--build] [--no-start] [--non-interactive] [--dry-run] [--json]

Deploy configured compose services on a remote server.

The basic native deploy command runs on the remote host:
  cd DEPLOY_PATH
  docker compose -f FILE pull [COMPOSE_SERVICE]
  docker compose -f FILE build [COMPOSE_SERVICE]
  docker compose -f FILE up -d [COMPOSE_SERVICE]

If the project has no deployment connection, an interactive terminal opens the
same saved/create/project-only/defer selector used by `ops setup`.

EOF
  container_usage_common
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service=*) SERVICE="${1#*=}" ;;
    --service)
      [[ $# -ge 2 ]] || die "--service requires an id" 2
      SERVICE="$2"
      shift
      ;;
    --compose-service=*) COMPOSE_SERVICE="${1#*=}" ;;
    --compose-service)
      [[ $# -ge 2 ]] || die "--compose-service requires a name" 2
      COMPOSE_SERVICE="$2"
      shift
      ;;
    --all) ALL=true ;;
    --tag=*) TAG="${1#*=}" ;;
    --tag)
      [[ $# -ge 2 ]] || die "--tag requires a value" 2
      TAG="$2"
      shift
      ;;
    --pull-only) PULL_ONLY=true ;;
    --no-pull) NO_PULL=true ;;
    --build) BUILD=true ;;
    --no-start) NO_START=true ;;
    --non-interactive) NON_INTERACTIVE=true ;;
    --dry-run) DRY_RUN=true ;;
    --json) JSON=true ;;
    --help|-h) _usage_deploy; exit 0 ;;
    --*) die "Unknown deploy flag: $1" 2 ;;
    *)
      if [[ -z "${SERVICE}" ]]; then
        SERVICE="$1"
      elif [[ -z "${COMPOSE_SERVICE}" ]]; then
        COMPOSE_SERVICE="$1"
      else
        die "Unexpected deploy argument: $1" 2
      fi
      ;;
  esac
  shift
done

require_bins jq
project_require_config_or_yaml
if [[ "${PULL_ONLY}" == "true" ]]; then
  NO_START=true
fi
if [[ "${NO_PULL}" == "true" && "${BUILD}" != "true" && "${NO_START}" == "true" ]]; then
  die "Deploy plan has no enabled stages." 2
fi
container_load_ci_env
[[ -n "${TAG}" ]] || TAG="$(container_default_tag)"

_deploy_connection_ready() {
  local raw ref resolved host user path
  raw="$(container_ci_config_raw_json)"
  ref="$(jq -r '.global_profile // ""' <<< "${raw}")"
  if [[ -n "${ref}" ]] && ! global_profile_exists "${ref}"; then
    return 1
  fi
  resolved="$(global_profile_resolve_ci_json "${raw}")" || return 1
  host="${DEPLOY_HOST:-$(jq -r '.deploy.host // ""' <<< "${resolved}")}"
  user="${DEPLOY_USER:-$(jq -r '.deploy.user // ""' <<< "${resolved}")}"
  path="${DEPLOY_PATH:-$(jq -r '.deploy.path // ""' <<< "${resolved}")}"
  [[ -n "${host}" && -n "${user}" && -n "${path}" ]]
}

_deploy_can_prompt() {
  [[ "${NON_INTERACTIVE}" != "true" &&
     "${OPS_NON_INTERACTIVE:-false}" != "true" &&
     "${CI:-false}" != "true" &&
     "${JSON}" != "true" &&
     -t 0 ]]
}

_ensure_deploy_connection() {
  _deploy_connection_ready && return 0

  if _deploy_can_prompt; then
    printf '\nNo complete deployment connection is configured for this project.\n'
    printf 'Choose a saved connection, create one, enter project-only values, or defer.\n\n'
    bash "${_SELF_DIR}/ci.sh" setup --interactive --apply
    container_load_ci_env
    _deploy_connection_ready && return 0
    die "Deployment connection is still incomplete. Run: ops setup ci --interactive --apply" 2
  fi

  die "Deployment connection is not configured.
Run interactively: ops setup ci --interactive --apply
Or select one directly: ops global use NAME --apply" 2
}

_ensure_deploy_connection
REMOTE_TARGET="$(container_ssh_target)"
DEPLOY_PATH="$(container_deploy_path)"
SSH_ARGS_JSON="$(container_ssh_args_json)"

PLAN="$(container_build_plan_json "${SERVICE}" "${COMPOSE_SERVICE}" "${TAG}" "false" "false" | jq -c '[.[] | select((.compose_files | length) > 0)]')"
if [[ ( -n "${SERVICE}" || -n "${COMPOSE_SERVICE}" ) && "$(jq 'length' <<< "${PLAN}")" == "0" ]]; then
  die "No compose deploy target found for service: ${SERVICE:-*}${COMPOSE_SERVICE:+ / compose service: ${COMPOSE_SERVICE}}" 2
fi

if [[ "${JSON}" == "true" ]]; then
  jq -n \
    --arg tag "${TAG}" \
    --arg remote "${REMOTE_TARGET}" \
    --arg path "${DEPLOY_PATH}" \
    --argjson pull_only "${PULL_ONLY}" \
    --argjson no_pull "${NO_PULL}" \
    --argjson build "${BUILD}" \
    --argjson no_start "${NO_START}" \
    --argjson ssh_args "${SSH_ARGS_JSON}" \
    --argjson targets "${PLAN}" \
    '{tag: $tag, remote: $remote, deploy_path: $path, stages: {pull: ($no_pull | not), build: $build, start: ($no_start | not)}, pull_only: $pull_only, no_pull: $no_pull, build: $build, no_start: $no_start, ssh_args: $ssh_args, targets: $targets}'
  exit 0
fi

ops_section "ops deploy"
if [[ "$(jq 'length' <<< "${PLAN}")" == "0" ]]; then
  ops_info "No compose deploy targets found."
  exit 0
fi

ssh_args=()
while IFS= read -r arg; do
  ssh_args+=("${arg}")
done < <(jq -r '.[]' <<< "${SSH_ARGS_JSON}")

run_remote() {
  local cmd="$1"
  printf '  ssh'
  local arg
  for arg in "${ssh_args[@]}"; do
    printf ' %s' "$(container_shell_quote "${arg}")"
  done
  printf ' %s %s\n' "$(container_shell_quote "${REMOTE_TARGET}")" "$(container_shell_quote "${cmd}")"
  if [[ "${DRY_RUN}" != "true" ]]; then
    ssh "${ssh_args[@]}" "${REMOTE_TARGET}" "${cmd}"
  fi
}

print_deploy_plan_summary() {
  local target service compose_service compose_files
  printf 'Deployment plan:\n'
  printf '  tag: %s\n' "${TAG}"
  printf '  remote: %s\n' "${REMOTE_TARGET}"
  printf '  deploy path: %s\n' "${DEPLOY_PATH}"
  printf '  pull: %s\n' "$([[ "${NO_PULL}" == "true" ]] && printf 'false' || printf 'true')"
  printf '  build: %s\n' "${BUILD}"
  printf '  start: %s\n' "$([[ "${NO_START}" == "true" ]] && printf 'false' || printf 'true')"
  printf '  targets:\n'
  while IFS= read -r target; do
    [[ -n "${target}" ]] || continue
    service="$(jq -r '.service' <<< "${target}")"
    compose_service="$(jq -r '.compose_service // ""' <<< "${target}")"
    compose_files="$(jq -r '(.compose_files // []) | join(", ")' <<< "${target}")"
    if [[ -n "${compose_service}" ]]; then
      printf '    - target: %s/%s\n' "${service}" "${compose_service}"
    else
      printf '    - target: %s\n' "${service}"
    fi
    printf '      compose files: %s\n' "${compose_files:-<none>}"
    printf '      compose service: %s\n' "${compose_service:-<all>}"
  done < <(jq -c '.[]' <<< "${PLAN}")
  printf '\n'
}

print_deploy_plan_summary

while IFS= read -r target; do
  [[ -n "${target}" ]] || continue
  service="$(jq -r '.service' <<< "${target}")"
  compose_service="$(jq -r '.compose_service // ""' <<< "${target}")"
  compose_args=()
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    compose_args+=("-f" "${file}")
  done < <(jq -r '.compose_files[]?' <<< "${target}")

  compose_part="VERSION=$(container_shell_quote "${TAG}") docker compose"
  for arg in "${compose_args[@]}"; do
    compose_part+=" $(container_shell_quote "${arg}")"
  done
  compose_target_part=""
  if [[ -n "${compose_service}" ]]; then
    compose_target_part=" $(container_shell_quote "${compose_service}")"
  fi

  if [[ -n "${compose_service}" ]]; then
    ops_info "${service}/${compose_service}: remote compose deploy"
  else
    ops_info "${service}: remote compose deploy"
  fi
  if [[ "${NO_PULL}" != "true" ]]; then
    run_remote "cd $(container_shell_quote "${DEPLOY_PATH}") && ${compose_part} pull${compose_target_part}"
  fi
  if [[ "${BUILD}" == "true" ]]; then
    run_remote "cd $(container_shell_quote "${DEPLOY_PATH}") && ${compose_part} build${compose_target_part}"
  fi
  if [[ "${NO_START}" != "true" ]]; then
    run_remote "cd $(container_shell_quote "${DEPLOY_PATH}") && ${compose_part} up -d${compose_target_part}"
  fi
done < <(jq -c '.[]' <<< "${PLAN}")

if [[ "${DRY_RUN}" == "true" ]]; then
  ops_info "Dry-run only. No remote commands executed."
else
  ops_ok "Deploy complete."
fi
