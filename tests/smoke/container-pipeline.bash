#!/usr/bin/env bash
# Native container build/deploy smoke tests.

suite_container_pipeline() {
  local root json output
  root="$(fixture_copy container-pipeline)"

  json="$(ops_run "${root}" build --service=api --tag=test123 --json)"
  assert_eq "build json includes dockerfile target" "api" "$(jq -r '.targets[0].service' <<< "${json}")"
  assert_eq "build json dockerfile target has no compose service" "" "$(jq -r '.targets[0].compose_service' <<< "${json}")"
  assert_eq "build json image uses ci config" "registry.example.test/demo/sample-api:test123" "$(jq -r '.targets[0].image' <<< "${json}")"
  assert_eq "build json strategy is dockerfile" "dockerfile" "$(jq -r '.targets[0].strategy' <<< "${json}")"

  output="$(ops_run "${root}" build --service=api --tag=test123 --push --dry-run)"
  case "${output}" in
    *"docker build"*sample-api:test123*"docker push"*) assert_eq "build dry-run prints build and push" "true" "true" ;;
    *) assert_eq "build dry-run prints build and push" "true" "false" ;;
  esac
  case "${output}" in
    *"Build plan:"*"target: api"*"image: registry.example.test/demo/sample-api:test123"*"context: backend"*"dockerfile: backend/Dockerfile"*) assert_eq "build dry-run explains dockerfile target" "true" "true" ;;
    *) assert_eq "build dry-run explains dockerfile target" "true" "false" ;;
  esac

  json="$(ops_run "${root}" build backend --tag=test123 --json)"
  assert_eq "positional compose build resolves owning service" "infra" "$(jq -r '.targets[0].service' <<< "${json}")"
  assert_eq "positional compose build resolves compose service" "backend" "$(jq -r '.targets[0].compose_service' <<< "${json}")"
  assert_eq "positional compose build strategy is compose" "compose" "$(jq -r '.targets[0].strategy' <<< "${json}")"

  output="$(ops_run "${root}" build backend --tag=test123 --push --dry-run)"
  case "${output}" in
    *"docker compose"*"build"*"backend"*"docker compose"*"push"*"backend"*) assert_eq "compose service build dry-run scopes build and push" "true" "true" ;;
    *) assert_eq "compose service build dry-run scopes build and push" "true" "false" ;;
  esac
  case "${output}" in
    *"Build plan:"*"target: infra/backend"*"compose files: infra/docker-compose.yml"*"compose service: backend"*) assert_eq "build dry-run explains compose target" "true" "true" ;;
    *) assert_eq "build dry-run explains compose target" "true" "false" ;;
  esac

  json="$(ops_run "${root}" build frontend --tag=test123 --json)"
  assert_eq "compose fallback resolves service path compose owner" "web" "$(jq -r '.targets[0].service' <<< "${json}")"
  assert_eq "compose fallback resolves nested compose service" "frontend" "$(jq -r '.targets[0].compose_service' <<< "${json}")"
  assert_eq "compose fallback records discovered compose file" "web/docker-compose.yml" "$(jq -r '.targets[0].compose_files[0]' <<< "${json}")"

  json="$(ops_run "${root}" deploy --service=infra --tag=test123 --json)"
  assert_eq "deploy json includes compose target" "infra" "$(jq -r '.targets[0].service' <<< "${json}")"
  assert_eq "deploy json remote from ci config" "deploy@deploy.example.test" "$(jq -r '.remote' <<< "${json}")"
  assert_eq "deploy json path from ci config" "/srv/sample" "$(jq -r '.deploy_path' <<< "${json}")"
  assert_eq "deploy json default stages" "true,false,true" "$(jq -r '[.stages.pull,.stages.build,.stages.start] | join(",")' <<< "${json}")"

  output="$(ops_run "${root}" deploy --service=infra --dry-run)"
  case "${output}" in
    *VERSION=latest*docker*compose*infra/docker-compose.yml*pull*VERSION=latest*docker*compose*infra/docker-compose.yml*up*-d*) assert_eq "deploy dry-run prints pull and up" "true" "true" ;;
    *) assert_eq "deploy dry-run prints pull and up" "true" "false" ;;
  esac

  json="$(ops_run "${root}" deploy --service=infra --no-pull --build --no-start --tag=test123 --json)"
  assert_eq "deploy json build-only stages" "false,true,false" "$(jq -r '[.stages.pull,.stages.build,.stages.start] | join(",")' <<< "${json}")"

  output="$(ops_run "${root}" deploy --service=infra --no-pull --build --no-start --dry-run)"
  case "${output}" in
    *"pull: false"*"build: true"*"start: false"*docker*compose*build*) assert_eq "deploy build-only dry-run prints build without activation" "true" "true" ;;
    *) assert_eq "deploy build-only dry-run prints build without activation" "true" "false" ;;
  esac
  case "${output}" in
    *docker*compose*pull*|*docker*compose*up*-d*) assert_eq "deploy build-only omits pull and start commands" "false" "true" ;;
    *) assert_eq "deploy build-only omits pull and start commands" "false" "false" ;;
  esac

  assert_fail "deploy rejects plan with all stages disabled" 2 \
    ops_run "${root}" deploy --service=infra --no-pull --no-start --dry-run

  json="$(ops_run "${root}" deploy backend --tag=test123 --json)"
  assert_eq "positional deploy resolves owning service" "infra" "$(jq -r '.targets[0].service' <<< "${json}")"
  assert_eq "positional deploy resolves compose service" "backend" "$(jq -r '.targets[0].compose_service' <<< "${json}")"

  output="$(ops_run "${root}" deploy backend --dry-run)"
  case "${output}" in
    *docker*compose*pull*backend*docker*compose*up*-d*backend*) assert_eq "compose service deploy dry-run scopes pull and up" "true" "true" ;;
    *) assert_eq "compose service deploy dry-run scopes pull and up" "true" "false" ;;
  esac
  case "${output}" in
    *"Deployment plan:"*"remote: deploy@deploy.example.test"*"deploy path: /srv/sample"*"target: infra/backend"*"compose service: backend"*) assert_eq "deploy dry-run explains remote compose target" "true" "true" ;;
    *) assert_eq "deploy dry-run explains remote compose target" "true" "false" ;;
  esac
}
