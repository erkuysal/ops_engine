#!/usr/bin/env bash
# .ops/core/lib/discovery.sh - Structured workspace discovery.

set -euo pipefail
if [[ "${_OPS_CORE_DISCOVERY_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_DISCOVERY_LOADED=1

# shellcheck source=detect.sh
source "${OPS_CORE_ROOT}/lib/detect.sh"
# shellcheck source=env_discovery.sh
source "${OPS_CORE_ROOT}/lib/env_discovery.sh"

OPS_DISCOVERY_FILE="${OPS_PROJECT_GENERATED_DIR:-${OPS_PROJECT_ROOT}/.ops.project/generated}/discovery.json"
export OPS_DISCOVERY_FILE

_discovery_json_string_array() {
  jq -Rn --arg raw "${1:-}" '$raw | split("\n") | map(select(length > 0))'
}

_discovery_docker_compose_files_json() {
  local rel_path="$1" abs_path="$2"
  local files_json='[]'
  local file rel
  local candidates=(
    compose.yml
    compose.yaml
    docker-compose.yml
    docker-compose.yaml
    docker-compose.override.yml
    docker-compose.override.yaml
  )

  for file in "${candidates[@]}"; do
    [[ -f "${abs_path}/${file}" ]] || continue
    rel="${rel_path}/${file}"
    files_json="$(jq --arg file "${rel}" '. + [$file]' <<< "${files_json}")"
  done

  printf '%s' "${files_json}"
}

_discovery_node_json() {
  local rel_path="$1" abs_path="$2" score="$3"
  local pkg="${abs_path}/package.json"
  local role="app" service=true confidence="0.70"
  local evidence=()
  local framework=""
  local package_name scripts_json deps_json
  local dev_script description

  package_name="$(jq -r '.name // ""' "${pkg}" 2>/dev/null || true)"
  description="$(jq -r '.description // ""' "${pkg}" 2>/dev/null || true)"
  dev_script="$(jq -r '.scripts.dev // ""' "${pkg}" 2>/dev/null || true)"
  scripts_json="$(jq -c '.scripts // {}' "${pkg}" 2>/dev/null || printf '{}')"
  deps_json="$(jq -c '(.dependencies // {}) + (.devDependencies // {}) + (.optionalDependencies // {})' "${pkg}" 2>/dev/null || printf '{}')"

  evidence+=("package.json")

  if jq -e '.workspaces? != null' "${pkg}" >/dev/null 2>&1; then
    role="workspace_root"
    service=false
    confidence="0.95"
    evidence+=("workspaces")
  elif jq -e '.devDependencies.electron? or .dependencies.electron? or (.main? | test("electron"; "i"))' "${pkg}" >/dev/null 2>&1; then
    role="app"
    service=true
    confidence="0.90"
    framework="electron"
    evidence+=("electron")
  elif jq -e '(.description? // "" | test("shared|library"; "i")) or (.keywords? // [] | any(. == "shared" or . == "library")) or ((.main? != null or .types? != null) and (.scripts.start? == null))' "${pkg}" >/dev/null 2>&1; then
    role="shared_library"
    service=false
    confidence="0.84"
    evidence+=("library metadata")
  elif jq -e '.dependencies.vue? or .dependencies.react? or .devDependencies["@vitejs/plugin-vue"]?' "${pkg}" >/dev/null 2>&1 || [[ "${dev_script}" == *vite* ]]; then
    role="app"
    service=true
    confidence="0.88"
    if jq -e '.dependencies.vue? or .devDependencies["@vitejs/plugin-vue"]?' "${pkg}" >/dev/null 2>&1; then
      framework="vue-vite"
      evidence+=("vue")
    elif jq -e '.dependencies.react?' "${pkg}" >/dev/null 2>&1; then
      framework="react"
      evidence+=("react")
    else
      framework="vite"
    fi
    evidence+=("vite")
  elif jq -e '.scripts.start? or .scripts.dev?' "${pkg}" >/dev/null 2>&1; then
    role="app"
    service=true
    confidence="0.75"
    evidence+=("start/dev script")
  else
    role="shared_library"
    service=false
    confidence="0.72"
    evidence+=("no start/dev script")
  fi

  jq -n \
    --arg path "${rel_path}" \
    --arg stack "node" \
    --arg role "${role}" \
    --argjson service "${service}" \
    --argjson score "${score}" \
    --arg confidence "${confidence}" \
    --arg package_name "${package_name}" \
    --arg framework "${framework}" \
    --argjson scripts "${scripts_json}" \
    --argjson deps "${deps_json}" \
    --argjson evidence "$(_discovery_json_string_array "$(printf '%s\n' "${evidence[@]}")")" \
    '{
      path: $path,
      stack: $stack,
      role: $role,
      service: $service,
      confidence: ($confidence | tonumber),
      score: $score,
      package: {name: $package_name, framework: $framework, scripts: $scripts},
      evidence: $evidence
    }'
}

_discovery_go_outputs_json() {
  local abs_path="$1"
  local entries_json='[]'
  local cmd_dir name out_name

  [[ -d "${abs_path}/cmd" ]] || {
    printf '[]'
    return 0
  }

  while IFS= read -r cmd_dir; do
    [[ -z "${cmd_dir}" ]] && continue
    [[ -f "${cmd_dir}/main.go" ]] || continue
    name="$(basename "${cmd_dir}")"
    out_name="${name#worker-}"
    entries_json="$(jq \
      --arg name "${out_name}" \
      --arg package "./cmd/${name}" \
      '. + [{name: $name, package: $package}]' \
      <<< "${entries_json}")"
  done < <(find "${abs_path}/cmd" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

  printf '%s' "${entries_json}"
}

_discovery_go_json() {
  local rel_path="$1" abs_path="$2" score="$3"
  local outputs_json role="app" service=true confidence="0.75"
  local evidence=("go.mod")
  outputs_json="$(_discovery_go_outputs_json "${abs_path}")"

  if [[ "$(jq 'length' <<< "${outputs_json}")" -gt 1 ]]; then
    role="process_group"
    service=true
    confidence="0.92"
    evidence+=("cmd/*")
  elif [[ "$(jq 'length' <<< "${outputs_json}")" -eq 1 ]]; then
    role="app"
    service=true
    confidence="0.82"
    evidence+=("cmd/*")
  elif [[ -f "${abs_path}/main.go" ]]; then
    role="app"
    service=true
    confidence="0.80"
    evidence+=("main.go")
  fi

  jq -n \
    --arg path "${rel_path}" \
    --arg stack "go" \
    --arg role "${role}" \
    --argjson service "${service}" \
    --argjson score "${score}" \
    --arg confidence "${confidence}" \
    --argjson outputs "${outputs_json}" \
    --argjson evidence "$(_discovery_json_string_array "$(printf '%s\n' "${evidence[@]}")")" \
    '{
      path: $path,
      stack: $stack,
      role: $role,
      service: $service,
      confidence: ($confidence | tonumber),
      score: $score,
      build: {outputs: $outputs},
      evidence: $evidence
    }'
}

_discovery_generic_json() {
  local rel_path="$1" abs_path="$2" stack="$3" score="$4"
  local role="app" service=true confidence="0.70"
  local evidence=("${stack} probe")
  local compose_files='[]'

  case "${stack}" in
    django) role="api"; confidence="0.88"; evidence=("manage.py") ;;
    elixir-phoenix) role="api"; confidence="0.86"; evidence=("mix.exs" "phoenix config") ;;
    docker)
      role="docker_group"
      confidence="0.75"
      compose_files="$(_discovery_docker_compose_files_json "${rel_path}" "${abs_path}")"
      if [[ "$(jq 'length' <<< "${compose_files}")" -gt 0 ]]; then
        evidence=("docker compose")
      else
        evidence=("docker files")
      fi
      ;;
  esac

  jq -n \
    --arg path "${rel_path}" \
    --arg stack "${stack}" \
    --arg role "${role}" \
    --argjson service "${service}" \
    --argjson score "${score}" \
    --arg confidence "${confidence}" \
    --argjson compose_files "${compose_files}" \
    --argjson evidence "$(_discovery_json_string_array "$(printf '%s\n' "${evidence[@]}")")" \
    '{
      path: $path,
      stack: $stack,
      role: $role,
      service: $service,
      confidence: ($confidence | tonumber),
      score: $score,
      compose_files: (if $stack == "docker" then $compose_files else [] end),
      evidence: $evidence
    }'
}

discovery_scan_project_json() {
  require_bins jq

  local entries_json='[]'
  local id rel_path stack score abs_path entry_json

  while IFS=$'\t' read -r id rel_path stack score; do
    [[ -z "${id}" ]] && continue
    abs_path="${OPS_PROJECT_ROOT}/${rel_path}"
    case "${stack}" in
      node) entry_json="$(_discovery_node_json "${rel_path}" "${abs_path}" "${score}")" ;;
      go) entry_json="$(_discovery_go_json "${rel_path}" "${abs_path}" "${score}")" ;;
      *) entry_json="$(_discovery_generic_json "${rel_path}" "${abs_path}" "${stack}" "${score}")" ;;
    esac
    entry_json="$(env_discovery_attach_to_entry_json "${entry_json}" "${rel_path}")"
    entries_json="$(jq --arg id "${id}" --argjson entry "${entry_json}" '. + [$entry + {id: $id}]' <<< "${entries_json}")"
  done < <(detect_scan_project)

  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --arg root "${OPS_PROJECT_ROOT}" \
    --argjson global_env_files "$(env_discovery_global_files_json)" \
    --argjson directories "${entries_json}" \
    '{
      version: 1,
      generated_at: $generated_at,
      project_root: $root,
      global_env_files: $global_env_files,
      directories: $directories
    }'
}

discovery_write_project_json() {
  ensure_dir "$(dirname "${OPS_DISCOVERY_FILE}")"
  discovery_scan_project_json > "${OPS_DISCOVERY_FILE}"
  printf '%s' "${OPS_DISCOVERY_FILE}"
}
