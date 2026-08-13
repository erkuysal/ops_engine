#!/usr/bin/env bash
# .ops/core/commands/ship.sh - Unified delivery pipeline planner.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/output.sh"
source "${_SELF_DIR}/../lib/shipping.sh"

PIPELINE=""
JOB=""
TAG=""
CONFIG_FILE="${OPS_SHIPPING_CONFIG_FILE}"
ONLY_STAGE=""
BUILD=true
PUBLISH=true
TRANSFER=true
DEPLOY=true
VERIFY=true
DRY_RUN=false
JSON=false

usage_ship() {
  cat <<'EOF'
Usage: ops ship [PIPELINE] [OPTIONS]

Plan one delivery pipeline containing Docker, file-sync, Git, and custom-script
jobs. Shipping uses the lifecycle: build -> publish -> transfer -> deploy -> verify.

Selection:
  --pipeline=NAME       Pipeline name (positional NAME is also accepted)
  --job=ID              Limit the plan to one configured job
  --tag=TAG             Artifact/release tag (default: VERSION, then latest)
  --config=PATH         Shipping config (default: .ops.project/config/shipping.json)
  --only=STAGE          Select only build, publish, transfer, deploy, or verify

Stage controls:
  --no-build            Skip build actions
  --no-publish          Skip artifact publication
  --no-push             Alias for --no-publish
  --no-transfer         Skip file/Git/config transfer
  --no-sync             Alias for --no-transfer
  --no-deploy           Skip activation/deployment
  --no-verify           Skip post-deployment verification

Output:
  --dry-run             Print the deterministic plan without executing it
  --json                Print the plan as JSON (implies --dry-run)

This first implementation is planning-only. Execution is intentionally blocked
until driver execution, receipts, resume, and rollback semantics are available.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pipeline=*) PIPELINE="${1#*=}" ;;
    --pipeline)
      [[ $# -ge 2 ]] || die "--pipeline requires a name" 2
      PIPELINE="$2"; shift
      ;;
    --job=*) JOB="${1#*=}" ;;
    --job)
      [[ $# -ge 2 ]] || die "--job requires an id" 2
      JOB="$2"; shift
      ;;
    --tag=*) TAG="${1#*=}" ;;
    --tag)
      [[ $# -ge 2 ]] || die "--tag requires a value" 2
      TAG="$2"; shift
      ;;
    --config=*) CONFIG_FILE="${1#*=}" ;;
    --config)
      [[ $# -ge 2 ]] || die "--config requires a path" 2
      CONFIG_FILE="$2"; shift
      ;;
    --only=*) ONLY_STAGE="${1#*=}" ;;
    --only)
      [[ $# -ge 2 ]] || die "--only requires a stage" 2
      ONLY_STAGE="$2"; shift
      ;;
    --no-build) BUILD=false ;;
    --no-publish|--no-push) PUBLISH=false ;;
    --no-transfer|--no-sync) TRANSFER=false ;;
    --no-deploy) DEPLOY=false ;;
    --no-verify) VERIFY=false ;;
    --dry-run) DRY_RUN=true ;;
    --json) JSON=true; DRY_RUN=true ;;
    --help|-h) usage_ship; exit 0 ;;
    --*) die "Unknown ship flag: $1" 2 ;;
    *)
      if [[ -z "${PIPELINE}" ]]; then
        PIPELINE="$1"
      else
        die "Unexpected ship argument: $1" 2
      fi
      ;;
  esac
  shift
done

case "${ONLY_STAGE}" in
  ""|build|publish|transfer|deploy|verify) ;;
  *) die "Unknown shipping stage for --only: ${ONLY_STAGE}" 2 ;;
esac

require_bins jq
CONFIG_FILE="$(shipping_expand_config_path "${CONFIG_FILE}")"
shipping_validate_config "${CONFIG_FILE}"
[[ -n "${PIPELINE}" ]] || PIPELINE="$(shipping_default_pipeline "${CONFIG_FILE}")"
[[ -n "${TAG}" ]] || {
  if [[ -f "${OPS_PROJECT_ROOT}/VERSION" ]]; then
    TAG="$(tr -d '[:space:]' < "${OPS_PROJECT_ROOT}/VERSION" | sed 's/^v//' | sed -n '1p')"
  fi
  TAG="${TAG:-latest}"
}

if ! jq -e --arg name "${PIPELINE}" '.pipelines[$name] != null' "${CONFIG_FILE}" >/dev/null; then
  die "Unknown shipping pipeline: ${PIPELINE}" 2
fi
if [[ -n "${JOB}" ]] && ! jq -e --arg pipeline "${PIPELINE}" --arg job "${JOB}" \
  '.pipelines[$pipeline].jobs | any(.id == $job)' "${CONFIG_FILE}" >/dev/null; then
  die "Unknown shipping job in ${PIPELINE}: ${JOB}" 2
fi

PLAN="$(shipping_plan_json "${CONFIG_FILE}" "${PIPELINE}" "${JOB}" "${TAG}" "${ONLY_STAGE}" \
  "${BUILD}" "${PUBLISH}" "${TRANSFER}" "${DEPLOY}" "${VERIFY}")"

if [[ "${JSON}" == "true" ]]; then
  jq . <<< "${PLAN}" | ops_json_envelope "ship"
  exit 0
fi

ops_section "ops ship"
printf 'Pipeline: %s\n' "$(jq -r '.pipeline' <<< "${PLAN}")"
printf 'Target:   %s\n' "$(jq -r '.target | if length == 0 then "<job-defined>" else . end' <<< "${PLAN}")"
printf 'Tag:      %s\n' "$(jq -r '.tag' <<< "${PLAN}")"
printf 'Mode:     plan only\n\n'
printf 'Actions:\n'
while IFS=$'\t' read -r selected job driver stage operation target reason; do
  if [[ "${selected}" == "true" ]]; then
    printf '  RUN   %-16s %-10s %-26s target=%s driver=%s\n' "${job}" "${stage}" "${operation}" "${target:-<local>}" "${driver}"
  else
    printf '  SKIP  %-16s %-10s %-26s %s\n' "${job}" "${stage}" "${operation}" "${reason}"
  fi
done < <(jq -r '.actions[] | [.selected, .job, .driver, .stage, .operation, .target, .skip_reason] | @tsv' <<< "${PLAN}")

selected_count="$(jq '[.actions[] | select(.selected)] | length' <<< "${PLAN}")"
printf '\nSelected actions: %s\n' "${selected_count}"

if [[ "${DRY_RUN}" == "true" ]]; then
  ops_info "Dry-run only. No build, publish, transfer, deploy, or verification action executed."
  exit 0
fi

die "Shipping execution is not enabled yet. Review the plan with --dry-run or --json." 2
