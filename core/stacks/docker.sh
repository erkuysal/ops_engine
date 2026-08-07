#!/usr/bin/env bash
# .ops-core/stacks/docker.sh — Docker/Compose stack strategy.

set -euo pipefail

_DOCKER_STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/init.sh
source "${_DOCKER_STACK_DIR}/../lib/init.sh"
# shellcheck source=../lib/manifest.sh
source "${_DOCKER_STACK_DIR}/../lib/manifest.sh"
# shellcheck source=../lib/command_exec.sh
source "${_DOCKER_STACK_DIR}/../lib/command_exec.sh"

_docker_collect_compose_files() {
  local files=() file
  while IFS= read -r file; do
    [[ -n "${file}" && "${file}" != "null" ]] && files+=("${file}")
  done < <(manifest_get_service_list_field "${OPS_SERVICE_ID}" compose_files 2>/dev/null || true)

  if [[ ${#files[@]} -eq 0 ]]; then
    local fallback
    for fallback in compose.yml compose.yaml docker-compose.yml docker-compose.yaml; do
      [[ -f "${fallback}" ]] && files+=("${fallback}")
    done
  fi

  printf '%s\n' "${files[@]}"
}

_docker_compose_cmd() {
  local files=() file args=()
  while IFS= read -r file; do
    [[ -n "${file}" ]] && files+=("${file}")
  done < <(_docker_collect_compose_files)

  [[ ${#files[@]} -gt 0 ]] || return 1
  for file in "${files[@]}"; do
    args+=(-f "${file}")
  done
  docker compose "${args[@]}" "$@"
}

docker_dispatch() {
  local action="${1:-}"
  local explicit_cmd="${2:-}"

  if [[ -n "${explicit_cmd}" && "${explicit_cmd}" != "null" ]]; then
    ops_run_configured_command "${explicit_cmd}"
    return $?
  fi

  case "${action}" in
    start) _docker_compose_cmd up -d || return 10 ;;
    stop) _docker_compose_cmd down || return 10 ;;
    logs) _docker_compose_cmd logs -f || return 10 ;;
    status)
      if _docker_compose_cmd ps --services --filter "status=running" | grep -q .; then
        return 0
      fi
      return 1
      ;;
    *)
      return 10
      ;;
  esac
}
