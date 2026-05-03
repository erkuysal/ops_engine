#!/usr/bin/env bash
# .ops-core/stacks/docker.sh — Docker/Compose stack strategy stub.

set -euo pipefail

docker_dispatch() {
  local action="${1:-}"
  local explicit_cmd="${2:-}"

  if [[ -n "${explicit_cmd}" && "${explicit_cmd}" != "null" ]]; then
    eval "${explicit_cmd}"
    return $?
  fi

  case "${action}" in
    start)
      if [[ -f docker-compose.yml || -f docker-compose.yaml ]]; then
        docker compose up -d
      else
        return 10
      fi
      return $?
      ;;
    stop)
      if [[ -f docker-compose.yml || -f docker-compose.yaml ]]; then
        docker compose down
      else
        return 10
      fi
      return $?
      ;;
    logs)
      if [[ -f docker-compose.yml || -f docker-compose.yaml ]]; then
        docker compose logs -f
      else
        return 10
      fi
      return $?
      ;;
    stop)
      if [[ -f docker-compose.yml || -f docker-compose.yaml ]]; then
        docker compose stop
      else
        return 10
      fi
      return $?
      ;;
    status)
      if [[ -f docker-compose.yml || -f docker-compose.yaml ]]; then
        # Check if any container for this compose project is running
        if docker compose ps --services --filter "status=running" | grep -q .; then
          return 0
        else
          return 1
        fi
      fi
      return 10
      ;;
    *)
      return 10
      ;;
  esac
}
