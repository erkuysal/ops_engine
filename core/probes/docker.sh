#!/usr/bin/env bash

probe_docker_stack_id() {
  printf 'docker'
}

probe_docker_score_dir() {
  local dir="$1"
  local score=0
  [[ -f "${dir}/Dockerfile" ]] && score=$((score + 3))
  [[ -f "${dir}/compose.yml" ]] && score=$((score + 2))
  [[ -f "${dir}/compose.yaml" ]] && score=$((score + 2))
  [[ -f "${dir}/docker-compose.yml" ]] && score=$((score + 1))
  [[ -f "${dir}/docker-compose.yaml" ]] && score=$((score + 1))
  [[ -f "${dir}/docker-compose.override.yml" ]] && score=$((score + 1))
  [[ -f "${dir}/docker-compose.override.yaml" ]] && score=$((score + 1))
  printf '%d' "${score}"
}
