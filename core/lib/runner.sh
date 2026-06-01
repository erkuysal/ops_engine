#!/usr/bin/env bash
# .ops/core/lib/runner.sh — Runner kind inference (stack vs execution profile).

set -euo pipefail
if [[ "${_OPS_CORE_RUNNER_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_RUNNER_LOADED=1

# shellcheck source=manifest.sh
source "${OPS_CORE_ROOT}/lib/manifest.sh"

OPS_RUNNER_KINDS=(stack process_group compose)
export OPS_RUNNER_KINDS

# Map discovery role (+ optional stack) to runner.kind.
runner_kind_for_role() {
  local role="${1:?runner_kind_for_role: role required}"

  case "${role}" in
    process_group) printf 'process_group' ;;
    docker_group) printf 'compose' ;;
    *) printf 'stack' ;;
  esac
}

runner_is_managed_kind() {
  local kind="${1:-}"
  case "${kind}" in
    process_group|compose) return 0 ;;
    *) return 1 ;;
  esac
}

runner_service_managed() {
  local service_id="${1:?runner_service_managed: service id required}"
  local kind
  kind="$(manifest_get_service_field "${service_id}" "runner.kind" 2>/dev/null || true)"
  runner_is_managed_kind "${kind}"
}

# Infer runner JSON from a discovery directory entry object.
runner_json_from_directory() {
  local directory_json="$1"
  local role stack kind
  role="$(jq -r '.role // ""' <<< "${directory_json}")"
  kind="$(runner_kind_for_role "${role}")"
  jq -n --arg kind "${kind}" '{kind: $kind}'
}

# Infer optional build/run blocks for materialization (process_group only).
runner_build_json_from_directory() {
  local directory_json="$1" service_id="$2"
  local role outputs_json
  role="$(jq -r '.role // ""' <<< "${directory_json}")"
  [[ "${role}" == "process_group" ]] || {
    printf '{}'
    return 0
  }

  outputs_json="$(jq -c '.build.outputs // [] | map(select(.enabled != false) | {name, package})' <<< "${directory_json}")"
  jq -n \
    --arg service_id "${service_id}" \
    --argjson outputs "${outputs_json}" \
    '{
      output_dir: (".ops.project/generated/bin/" + $service_id),
      target_os: "linux",
      target_arch: "amd64",
      outputs: $outputs
    }'
}

runner_run_json_from_directory() {
  local directory_json="$1"
  local role outputs_json
  role="$(jq -r '.role // ""' <<< "${directory_json}")"
  [[ "${role}" == "process_group" ]] || {
    printf '{}'
    return 0
  }

  outputs_json="$(jq -c '.build.outputs // [] | map(select(.enabled != false) | {name})' <<< "${directory_json}")"
  jq -n --argjson processes "${outputs_json}" '{processes: $processes}'
}

return 0
