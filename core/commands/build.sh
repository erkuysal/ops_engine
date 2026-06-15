#!/usr/bin/env bash
# .ops/core/commands/build.sh - Native container build/push command.

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
PUSH=false
NO_CACHE=false
DRY_RUN=false
JSON=false

_usage_build() {
  cat <<'EOF'
Usage: ops build [SERVICE] [--service=ID|--all] [--compose-service=NAME] [--tag=TAG] [--push] [--no-cache] [--dry-run] [--json]

Build container images for configured services.

For Dockerfile services, ops runs:
  docker build -f DOCKERFILE -t IMAGE CONTEXT
  docker push IMAGE                when --push is set

For compose services, ops runs:
  docker compose -f FILE build [COMPOSE_SERVICE]
  docker compose -f FILE push [COMPOSE_SERVICE]      when --push is set

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
    --push) PUSH=true ;;
    --no-cache) NO_CACHE=true ;;
    --dry-run) DRY_RUN=true ;;
    --json) JSON=true ;;
    --help|-h) _usage_build; exit 0 ;;
    --*) die "Unknown build flag: $1" 2 ;;
    *)
      if [[ -z "${SERVICE}" ]]; then
        SERVICE="$1"
      elif [[ -z "${COMPOSE_SERVICE}" ]]; then
        COMPOSE_SERVICE="$1"
      else
        die "Unexpected build argument: $1" 2
      fi
      ;;
  esac
  shift
done

require_bins jq
require_manifest_or_config
container_load_ci_env
[[ -n "${TAG}" ]] || TAG="$(container_default_tag)"

if [[ -z "${SERVICE}" && "${ALL}" != "true" ]]; then
  SERVICE=""
fi

PLAN="$(container_build_plan_json "${SERVICE}" "${COMPOSE_SERVICE}" "${TAG}" "${PUSH}" "${NO_CACHE}")"
if [[ ( -n "${SERVICE}" || -n "${COMPOSE_SERVICE}" ) && "$(jq 'length' <<< "${PLAN}")" == "0" ]]; then
  die "No buildable container target found for service: ${SERVICE:-*}${COMPOSE_SERVICE:+ / compose service: ${COMPOSE_SERVICE}}" 2
fi

if [[ "${JSON}" == "true" ]]; then
  jq -n --arg tag "${TAG}" --argjson push "${PUSH}" --argjson targets "${PLAN}" \
    '{tag: $tag, push: $push, targets: $targets}'
  exit 0
fi

ops_section "ops build"
if [[ "$(jq 'length' <<< "${PLAN}")" == "0" ]]; then
  ops_info "No buildable container targets found."
  exit 0
fi

run_cmd() {
  local -a cmd=("$@")
  printf '  '
  local arg
  for arg in "${cmd[@]}"; do
    printf '%s ' "$(container_shell_quote "${arg}")"
  done
  printf '\n'
  if [[ "${DRY_RUN}" != "true" ]]; then
    "${cmd[@]}"
  fi
}

print_build_plan_summary() {
  local target service strategy image context dockerfile compose_service compose_files
  printf 'Build plan:\n'
  printf '  tag: %s\n' "${TAG}"
  printf '  push: %s\n' "${PUSH}"
  printf '  no cache: %s\n' "${NO_CACHE}"
  printf '  targets:\n'
  while IFS= read -r target; do
    [[ -n "${target}" ]] || continue
    service="$(jq -r '.service' <<< "${target}")"
    strategy="$(jq -r '.strategy' <<< "${target}")"
    image="$(jq -r '.image' <<< "${target}")"
    context="$(jq -r '.context' <<< "${target}")"
    dockerfile="$(jq -r '.dockerfile' <<< "${target}")"
    compose_service="$(jq -r '.compose_service // ""' <<< "${target}")"
    compose_files="$(jq -r '(.compose_files // []) | join(", ")' <<< "${target}")"

    if [[ -n "${compose_service}" ]]; then
      printf '    - target: %s/%s\n' "${service}" "${compose_service}"
    else
      printf '    - target: %s\n' "${service}"
    fi
    printf '      strategy: %s\n' "${strategy}"
    if [[ "${strategy}" == "compose" ]]; then
      printf '      compose files: %s\n' "${compose_files:-<none>}"
      printf '      compose service: %s\n' "${compose_service:-<all>}"
    else
      printf '      image: %s\n' "${image}"
      printf '      context: %s\n' "${context}"
      printf '      dockerfile: %s\n' "${dockerfile}"
    fi
  done < <(jq -c '.[]' <<< "${PLAN}")
  printf '\n'
}

print_build_plan_summary

while IFS= read -r target; do
  [[ -n "${target}" ]] || continue
  service="$(jq -r '.service' <<< "${target}")"
  strategy="$(jq -r '.strategy' <<< "${target}")"
  image="$(jq -r '.image' <<< "${target}")"
  context="$(jq -r '.context' <<< "${target}")"
  dockerfile="$(jq -r '.dockerfile' <<< "${target}")"
  compose_service="$(jq -r '.compose_service // ""' <<< "${target}")"

  if [[ -n "${compose_service}" ]]; then
    ops_info "${service}/${compose_service}: ${strategy}"
  else
    ops_info "${service}: ${strategy}"
  fi
  if [[ "${strategy}" == "compose" ]]; then
    compose_args=()
    while IFS= read -r file; do
      [[ -n "${file}" ]] || continue
      compose_args+=("-f" "${file}")
    done < <(jq -r '.compose_files[]?' <<< "${target}")
    build_args=("env" "VERSION=${TAG}" "docker" "compose" "${compose_args[@]}" "build")
    [[ "${NO_CACHE}" == "true" ]] && build_args+=("--no-cache")
    [[ -n "${compose_service}" ]] && build_args+=("${compose_service}")
    run_cmd "${build_args[@]}"
    if [[ "${PUSH}" == "true" ]]; then
      push_args=("env" "VERSION=${TAG}" "docker" "compose" "${compose_args[@]}" "push")
      [[ -n "${compose_service}" ]] && push_args+=("${compose_service}")
      run_cmd "${push_args[@]}"
    fi
  else
    build_args=("docker" "build" "-f" "${dockerfile}" "-t" "${image}")
    [[ "${NO_CACHE}" == "true" ]] && build_args+=("--no-cache")
    build_args+=("${context}")
    run_cmd "${build_args[@]}"
    if [[ "${PUSH}" == "true" ]]; then
      run_cmd docker push "${image}"
    fi
  fi
done < <(jq -c '.[]' <<< "${PLAN}")

if [[ "${DRY_RUN}" == "true" ]]; then
  ops_info "Dry-run only. No commands executed."
else
  ops_ok "Build complete."
fi
