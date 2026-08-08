#!/usr/bin/env bash
# .ops/core/lib/container_pipeline.sh - Minimal native container build/deploy helpers.

set -euo pipefail
if [[ "${_OPS_CORE_CONTAINER_PIPELINE_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_CONTAINER_PIPELINE_LOADED=1

# shellcheck source=global_profiles.sh
source "${OPS_CORE_ROOT}/lib/global_profiles.sh"

OPS_CI_CONFIG_FILE="${OPS_PROJECT_CONFIG_DIR}/ci.json"

container_usage_common() {
  cat <<'EOF'
Common flags:
  --service=ID       Limit to one ops service
  --compose-service=NAME
                    Limit a compose target to one compose service
  --all              Include all eligible services
  --tag=TAG          Image tag/deploy version (default: VERSION file, then latest)
  --dry-run          Print commands without executing
  --json             Print planned commands as JSON

Image names come from service deploy.image or:
  ci.docker.registry / ci.docker.namespace / ci.docker.image_prefix / service id

Deploy connection comes from:
  .ops.project/config/ci.json and .ops.project/secrets/ci.env
EOF
}

container_expand_path() {
  local path="$1"
  path="${path/#\~/${HOME}}"
  case "${path}" in
    /*) printf '%s' "${path}" ;;
    *) printf '%s/%s' "${OPS_PROJECT_ROOT}" "${path}" ;;
  esac
}

container_shell_quote() {
  printf '%q' "$1"
}

container_ci_config_raw_json() {
  if [[ -f "${OPS_CI_CONFIG_FILE}" ]]; then
    cat "${OPS_CI_CONFIG_FILE}"
  else
    jq -n '{
      docker: {registry: "docker.io", namespace: "", image_prefix: ""},
      deploy: {host: "", user: "", path: "", ssh_key_path: ""},
      secrets: {local_env_file: ".ops.project/secrets/ci.env"}
    }'
  fi
}

container_ci_config_json() {
  global_profile_resolve_ci_json "$(container_ci_config_raw_json)"
}

container_ci_env_file() {
  jq -r '.secrets.local_env_file // ".ops.project/secrets/ci.env"' <<< "$(container_ci_config_raw_json)"
}

container_load_ci_env() {
  local env_file expanded line key value
  env_file="$(container_ci_env_file)"
  expanded="$(container_expand_path "${env_file}")"
  [[ -f "${expanded}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -n "${!key:-}" ]] || export "${key}=${value}"
  done < "${expanded}"
}

container_ci_value() {
  local expr="$1" env_name="$2" default="${3:-}" value
  value="${!env_name:-}"
  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
    return 0
  fi
  value="$(jq -r "${expr} // \"\"" <<< "$(container_ci_config_json)" 2>/dev/null || true)"
  [[ -n "${value}" && "${value}" != "null" ]] && printf '%s' "${value}" || printf '%s' "${default}"
}

container_default_tag() {
  if [[ -f "${OPS_PROJECT_ROOT}/VERSION" ]]; then
    tr -d '[:space:]' < "${OPS_PROJECT_ROOT}/VERSION" | sed 's/^v//' | sed -n '1p'
  else
    printf 'latest'
  fi
}

container_project_name() {
  local name
  if [[ -f "${OPS_PROJECT_CONFIG_DIR}/project.json" ]]; then
    name="$(jq -r '.name // empty' "${OPS_PROJECT_CONFIG_DIR}/project.json" 2>/dev/null | sed -n '1p')"
  fi
  [[ -n "${name:-}" ]] && printf '%s' "${name}" || basename "${OPS_PROJECT_ROOT}"
}

container_service_json_by_id() {
  local service_id="$1"
  jq -c --arg id "${service_id}" '.services[]? | select(.id == $id)' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null
}

container_service_ids() {
  jq -r '.services[]?.id' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null
}

container_service_json_items() {
  if [[ -f "${OPS_PROJECT_CONFIG_SERVICES_FILE}" ]]; then
    jq -c '.services[]?' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null
    return 0
  fi
  return 1
}

container_service_json_from_manifest() {
  local service_id="${1:?container_service_json_from_manifest: service id required}"
  local compose_files_json build_json runner_json setup_json
  compose_files_json="$(project_get_service_list_field "${service_id}" compose_files 2>/dev/null | jq -Rsc 'split("\n") | map(select(length > 0))')"
  build_json="$(jq -n \
    --arg context "$(project_get_service_field "${service_id}" "build.context" 2>/dev/null || true)" \
    --arg dockerfile "$(project_get_service_field "${service_id}" "build.dockerfile" 2>/dev/null || true)" \
    --arg image "$(project_get_service_field "${service_id}" "build.image" 2>/dev/null || true)" \
    --arg deploy_context "$(project_get_service_field "${service_id}" "deploy.context" 2>/dev/null || true)" \
    --arg deploy_dockerfile "$(project_get_service_field "${service_id}" "deploy.dockerfile" 2>/dev/null || true)" \
    --arg deploy_image "$(project_get_service_field "${service_id}" "deploy.image" 2>/dev/null || true)" \
    '{
      context: $context,
      dockerfile: $dockerfile,
      image: $image
    } + (if ($deploy_context != "" or $deploy_dockerfile != "" or $deploy_image != "") then
      {deploy: {context: $deploy_context, dockerfile: $deploy_dockerfile, image: $deploy_image}}
    else {} end)')"
  runner_json="$(jq -n --arg kind "$(project_get_service_field "${service_id}" "runner.kind" 2>/dev/null || true)" '{kind: $kind}')"
  setup_json="$(jq -n --arg port "$(project_get_service_field "${service_id}" "setup.port" 2>/dev/null || true)" '{port: ($port | tonumber? // 0)}')"
  jq -n \
    --arg id "${service_id}" \
    --arg name "$(project_get_service_field "${service_id}" name 2>/dev/null || true)" \
    --arg stack "$(project_get_service_field "${service_id}" stack 2>/dev/null || true)" \
    --arg path "$(project_get_service_field "${service_id}" path 2>/dev/null || true)" \
    --arg role "$(project_get_service_field "${service_id}" role 2>/dev/null || true)" \
    --argjson compose_files "${compose_files_json}" \
    --argjson build "${build_json}" \
    --argjson runner "${runner_json}" \
    --argjson setup "${setup_json}" \
    '{
      id: $id,
      name: $name,
      stack: $stack,
      path: $path,
      role: $role,
      runner: $runner,
      build: $build,
      deploy: ($build.deploy // {}),
      compose_files: $compose_files,
      setup: $setup
    }'
}

container_compose_files_args_json() {
  local svc_json="$1"
  local configured path candidate files='[]'
  configured="$(jq -c '(.compose_files // []) | map(select(length > 0))' <<< "${svc_json}")"
  if [[ "$(jq 'length' <<< "${configured}")" -gt 0 ]]; then
    printf '%s' "${configured}"
    return 0
  fi
  path="$(jq -r '.path // "."' <<< "${svc_json}")"
  [[ -n "${path}" && "${path}" != "null" ]] || path="."
  for candidate in compose.yml compose.yaml docker-compose.yml docker-compose.yaml docker-compose.override.yml docker-compose.override.yaml; do
    if [[ -f "${OPS_PROJECT_ROOT}/${path}/${candidate}" ]]; then
      if [[ "${path}" == "." ]]; then
        files="$(jq -c --arg file "${candidate}" '. + [$file]' <<< "${files}")"
      else
        files="$(jq -c --arg file "${path}/${candidate}" '. + [$file]' <<< "${files}")"
      fi
    fi
  done
  printf '%s' "${files}"
}

container_has_compose_files() {
  local svc_json="$1"
  [[ "$(container_compose_files_args_json "${svc_json}" | jq 'length')" -gt 0 ]]
}

container_service_id_exists() {
  local service_filter="$1" service_id
  [[ -n "${service_filter}" ]] || return 1
  while IFS= read -r service_id; do
    [[ "${service_id}" == "${service_filter}" ]] && return 0
  done < <(project_list_services)
  return 1
}

container_compose_service_names_json() {
  local compose_files_json="$1"
  local names='[]' file abs_file name
  command -v yq >/dev/null 2>&1 || {
    printf '[]'
    return 0
  }
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    abs_file="$(container_expand_path "${file}")"
    [[ -f "${abs_file}" ]] || continue
    while IFS= read -r name; do
      [[ -n "${name}" && "${name}" != "null" ]] || continue
      names="$(jq -c --arg name "${name}" 'if index($name) then . else . + [$name] end' <<< "${names}")"
    done < <(yq e '.services | keys | .[]' "${abs_file}" 2>/dev/null || true)
  done < <(jq -r '.[]?' <<< "${compose_files_json}")
  printf '%s' "${names}"
}

container_compose_service_exists() {
  local compose_files_json="$1" compose_service="$2"
  [[ -n "${compose_service}" ]] || return 1
  jq -e --arg name "${compose_service}" 'index($name) != null' \
    <<< "$(container_compose_service_names_json "${compose_files_json}")" >/dev/null
}

container_service_context() {
  local svc_json="$1" path context
  context="$(jq -r '.build.context // .deploy.context // ""' <<< "${svc_json}")"
  if [[ -n "${context}" && "${context}" != "null" ]]; then
    printf '%s' "${context}"
    return 0
  fi
  path="$(jq -r '.path // "."' <<< "${svc_json}")"
  printf '%s' "${path}"
}

container_service_dockerfile() {
  local svc_json="$1" context dockerfile
  dockerfile="$(jq -r '.build.dockerfile // .deploy.dockerfile // ""' <<< "${svc_json}")"
  if [[ -n "${dockerfile}" && "${dockerfile}" != "null" ]]; then
    printf '%s' "${dockerfile}"
    return 0
  fi
  context="$(container_service_context "${svc_json}")"
  if [[ -f "${OPS_PROJECT_ROOT}/${context}/Dockerfile" ]]; then
    printf '%s/Dockerfile' "${context}"
  fi
}

container_service_eligible_for_build() {
  local svc_json="$1"
  if container_has_compose_files "${svc_json}"; then
    return 0
  fi
  [[ -n "$(container_service_dockerfile "${svc_json}")" ]]
}

container_image_ref() {
  local svc_json="$1" tag="$2"
  local explicit registry namespace prefix service_id repo
  explicit="$(jq -r '.deploy.image // .build.image // ""' <<< "${svc_json}")"
  if [[ -n "${explicit}" && "${explicit}" != "null" ]]; then
    printf '%s' "${explicit//\{tag\}/${tag}}"
    return 0
  fi

  service_id="$(jq -r '.id' <<< "${svc_json}")"
  registry="$(container_ci_value '.docker.registry' DOCKER_REGISTRY 'docker.io')"
  namespace="$(container_ci_value '.docker.namespace' DOCKER_NAMESPACE '')"
  prefix="$(container_ci_value '.docker.image_prefix' DOCKER_IMAGE_PREFIX '')"
  [[ -n "${prefix}" ]] || prefix="$(container_project_name)"
  repo="${prefix}-${service_id}"
  repo="${repo//_/-}"

  if [[ -n "${namespace}" ]]; then
    repo="${namespace}/${repo}"
  fi
  if [[ -n "${registry}" && "${registry}" != "docker.io" ]]; then
    repo="${registry}/${repo}"
  fi
  printf '%s:%s' "${repo}" "${tag}"
}

container_build_plan_json() {
  local service_filter="$1" compose_service_filter="$2" tag="$3" push="$4" no_cache="$5"
  local plan='[]' service_id svc_json image context dockerfile compose_files compose_service exact_service_filter=false
  if container_service_id_exists "${service_filter}"; then
    exact_service_filter=true
  fi
  if [[ -n "${compose_service_filter}" || ( -n "${service_filter}" && "${exact_service_filter}" != "true" ) ]]; then
    command -v yq >/dev/null 2>&1 || die "yq is required to resolve compose service targets." 2
  fi
  while IFS= read -r service_id; do
    [[ -n "${service_id}" ]] || continue
    if [[ "${exact_service_filter}" == "true" && "${service_filter}" != "${service_id}" ]]; then
      continue
    fi
    svc_json="$(container_service_json_from_manifest "${service_id}")"
    [[ -n "${svc_json}" ]] || continue
    container_service_eligible_for_build "${svc_json}" || continue
    image="$(container_image_ref "${svc_json}" "${tag}")"
    context="$(container_service_context "${svc_json}")"
    dockerfile="$(container_service_dockerfile "${svc_json}")"
    compose_files="$(container_compose_files_args_json "${svc_json}")"
    compose_service=""
    if [[ "$(jq 'length' <<< "${compose_files}")" -gt 0 ]]; then
      if [[ -n "${compose_service_filter}" ]]; then
        container_compose_service_exists "${compose_files}" "${compose_service_filter}" || continue
        compose_service="${compose_service_filter}"
      elif [[ -n "${service_filter}" && "${exact_service_filter}" != "true" ]]; then
        container_compose_service_exists "${compose_files}" "${service_filter}" || continue
        compose_service="${service_filter}"
      elif [[ -n "${service_filter}" && "${service_filter}" == "${service_id}" ]] &&
        command -v yq >/dev/null 2>&1 &&
        container_compose_service_exists "${compose_files}" "${service_filter}"; then
        compose_service="${service_filter}"
      fi
    elif [[ -n "${compose_service_filter}" || ( -n "${service_filter}" && "${exact_service_filter}" != "true" ) ]]; then
      continue
    fi
    plan="$(jq -c \
      --arg id "${service_id}" \
      --arg compose_service "${compose_service}" \
      --arg image "${image}" \
      --arg context "${context}" \
      --arg dockerfile "${dockerfile}" \
      --argjson push "${push}" \
      --argjson no_cache "${no_cache}" \
      --argjson compose_files "${compose_files}" \
      '. + [{
        service: $id,
        compose_service: $compose_service,
        image: $image,
        context: $context,
        dockerfile: $dockerfile,
        compose_files: $compose_files,
        push: $push,
        no_cache: $no_cache,
        strategy: (if ($compose_files | length) > 0 then "compose" else "dockerfile" end)
      }]' <<< "${plan}")"
  done < <(project_list_services)
  printf '%s' "${plan}"
}

container_ssh_target() {
  local host user
  host="$(container_ci_value '.deploy.host' DEPLOY_HOST '')"
  user="$(container_ci_value '.deploy.user' DEPLOY_USER '')"
  [[ -n "${host}" && -n "${user}" ]] || die "Missing deploy host/user. Run: ops ci ssh-setup --interactive --apply" 2
  printf '%s@%s' "${user}" "${host}"
}

container_ssh_args_json() {
  local key_path
  key_path="${DEPLOY_SSH_KEY_PATH:-$(container_ci_value '.deploy.ssh_key_path' DEPLOY_SSH_KEY_PATH '')}"
  if [[ -n "${key_path}" && "${key_path}" != "null" ]]; then
    key_path="$(container_expand_path "${key_path}")"
    jq -c -n --arg key "${key_path}" '["-o","BatchMode=yes","-i",$key]'
  else
    jq -c -n '["-o","BatchMode=yes"]'
  fi
}

container_deploy_path() {
  container_ci_value '.deploy.path' DEPLOY_PATH ''
}
