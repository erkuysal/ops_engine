#!/usr/bin/env bash
# Generate project-owned shipping configuration through the setup lifecycle.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/shipping.sh"

APPLY=false
INTERACTIVE=false
REFRESH=false
JSON=false

usage_setup_shipping() {
  cat <<'EOF'
Usage: ops setup shipping [--interactive] [--refresh] [--apply] [--json]

Infer, review, and optionally materialize .ops.project/config/shipping.json.

  --interactive   Add or revise Docker Compose, file-sync, Git, or script jobs
  --refresh       Ignore the current shipping config and run inference again
  --apply         Write the reviewed proposal to project config
  --json          Print only the proposed configuration

Without --apply this command is preview-only. Existing configuration is
preserved unless --refresh is explicitly requested.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true ;;
    --interactive) INTERACTIVE=true ;;
    --refresh) REFRESH=true ;;
    --json) JSON=true ;;
    --dry-run) ;;
    --help|-h) usage_setup_shipping; exit 0 ;;
    *) die "Unknown setup shipping flag: $1" 2 ;;
  esac
  shift
done

require_bins jq

shipping_discover_compose_files() {
  find "${OPS_PROJECT_ROOT}" \
    \( -path '*/.git' -o -path '*/.ops' -o -path '*/.ops.project' -o -path '*/node_modules' -o -path '*/docs/archive' \) -prune -o \
    -type f \( \
      -name 'compose.yml' -o -name 'compose.yaml' -o \
      -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o \
      -name 'docker-compose.*.yml' -o -name 'docker-compose.*.yaml' -o \
      \( -path '*/deployment/compose/*' \( -name '*.yml' -o -name '*.yaml' \) \) \
    \) \
    -print 2>/dev/null |
    sed "s#^${OPS_PROJECT_ROOT}/##" |
    LC_ALL=C sort
}

shipping_pick_compose_file() {
  local kind="$1" files="$2" preferred candidate
  if [[ "${kind}" == "production" ]]; then
    for preferred in \
      deployment/compose/app/production.yml \
      docker-compose.yml \
      compose.yml; do
      grep -Fxq "${preferred}" <<< "${files}" && { printf '%s' "${preferred}"; return 0; }
    done
    candidate="$(grep -Ei '(^|[/._-])(production|prod)([/._-]|$)' <<< "${files}" | sed -n '1p' || true)"
  else
    for preferred in \
      deployment/compose/app/staging.yml \
      docker-compose.staging.yml; do
      grep -Fxq "${preferred}" <<< "${files}" && { printf '%s' "${preferred}"; return 0; }
    done
    candidate="$(grep -Ei '(^|[/._-])staging([/._-]|$)' <<< "${files}" | sed -n '1p' || true)"
  fi
  [[ -n "${candidate}" ]] && printf '%s' "${candidate}"
}

shipping_compose_job_json() {
  local id="$1" compose_file files='[]'
  shift
  local buildable=false
  for compose_file in "$@"; do
    files="$(jq -c --arg file "${compose_file}" '. + [$file]' <<< "${files}")"
    grep -Eq '^[[:space:]]+build:' "${OPS_PROJECT_ROOT}/${compose_file}" && buildable=true
  done
  jq -n --arg id "${id}" --argjson files "${files}" --argjson buildable "${buildable}" '{
    id: $id,
    uses: "docker.compose",
    compose_files: $files,
    project_directory: ".",
    verify: {kind: "compose_health", compose_files: $files}
  } + (if $buildable then {} else {build: false, publish: false} end)'
}

shipping_production_compose_jobs_json() {
  local files="$1" path id job jobs='[]' found=false
  while IFS=$'\t' read -r id path; do
    if grep -Fxq "${path}" <<< "${files}"; then
      job="$(shipping_compose_job_json "${id}" "${path}")"
      jobs="$(jq -c --argjson job "${job}" '. + [$job]' <<< "${jobs}")"
      found=true
    fi
  done <<'EOF'
app	deployment/compose/app/production.yml
web	deployment/compose/frontend/production.yml
ops	deployment/compose/platform/production.yml
edge	deployment/compose/edge/caddy.yml
EOF

  if [[ "${found}" == "true" ]]; then
    printf '%s' "${jobs}"
    return 0
  fi

  if grep -Fxq 'docker-compose.yml' <<< "${files}" && grep -Fxq 'deployment/compose/production.yml' <<< "${files}"; then
    job="$(shipping_compose_job_json application docker-compose.yml deployment/compose/production.yml)"
    jq -cn --argjson job "${job}" '[$job]'
    return 0
  fi
  if grep -Fxq 'compose.yml' <<< "${files}" && grep -Fxq 'deployment/compose/production.yml' <<< "${files}"; then
    job="$(shipping_compose_job_json application compose.yml deployment/compose/production.yml)"
    jq -cn --argjson job "${job}" '[$job]'
    return 0
  fi

  path="$(shipping_pick_compose_file production "${files}")"
  [[ -n "${path}" ]] || { printf '[]'; return 0; }
  job="$(shipping_compose_job_json application "${path}")"
  jq -cn --argjson job "${job}" '[$job]'
}

shipping_infer_config() {
  local files production_jobs staging_file fallback pipelines targets default_pipeline job repository checkout_job
  files="$(shipping_discover_compose_files)"
  production_jobs="$(shipping_production_compose_jobs_json "${files}")"
  staging_file="$(shipping_pick_compose_file staging "${files}")"
  pipelines='{}'
  targets='{}'
  default_pipeline=''

  if [[ "$(jq 'length' <<< "${production_jobs}")" -gt 0 ]]; then
    repository="$(git -C "${OPS_PROJECT_ROOT}" config --get remote.origin.url 2>/dev/null || true)"
    if [[ -n "${repository}" ]]; then
      checkout_job="$(jq -n --arg repository "${repository}" '{
        id: "source",
        uses: "git.checkout",
        repository: $repository,
        ref: "{tag}",
        destination: "."
      }')"
      production_jobs="$(jq -c --argjson checkout "${checkout_job}" \
        '[$checkout] + map(.depends_on = (((.depends_on // []) + ["source"]) | unique))' \
        <<< "${production_jobs}")"
    fi
    pipelines="$(jq -c --argjson jobs "${production_jobs}" '. + {
      production: {
        description: "Inferred production delivery pipeline",
        target: "production",
        jobs: $jobs
      }
    }' <<< "${pipelines}")"
    targets="$(jq -c '. + {production: {transport: "ssh", config_ref: "ci.deploy"}}' <<< "${targets}")"
    default_pipeline='production'
  fi

  if [[ -n "${staging_file}" ]]; then
    job="$(shipping_compose_job_json application "${staging_file}")"
    pipelines="$(jq -c --argjson job "${job}" '. + {
      staging: {
        description: "Inferred staging delivery pipeline",
        target: "staging",
        jobs: [$job]
      }
    }' <<< "${pipelines}")"
    targets="$(jq -c '. + {staging: {transport: "ssh", config_ref: "ci.deploy.staging"}}' <<< "${targets}")"
    [[ -n "${default_pipeline}" ]] || default_pipeline='staging'
  fi

  if [[ "$(jq 'length' <<< "${pipelines}")" == "0" ]]; then
    fallback="$(sed -n '1p' <<< "${files}")"
    [[ -n "${fallback}" ]] || die "No shipping workflow could be inferred. Run ops setup shipping --interactive to configure one." 2
    job="$(shipping_compose_job_json application "${fallback}")"
    pipelines="$(jq -c --argjson job "${job}" '. + {
      local: {
        description: "Inferred local delivery pipeline",
        target: "local",
        jobs: [$job]
      }
    }' <<< "${pipelines}")"
    targets='{"local":{"transport":"local"}}'
    default_pipeline='local'
  fi

  jq -n \
    --argjson version 1 \
    --arg generated_at "$(ops_timestamp)" \
    --arg default_pipeline "${default_pipeline}" \
    --argjson targets "${targets}" \
    --argjson pipelines "${pipelines}" \
    '{
      version: $version,
      generated_at: $generated_at,
      source: "ops_setup_shipping",
      default_pipeline: $default_pipeline,
      targets: $targets,
      pipelines: $pipelines
    }'
}

shipping_prompt() {
  local label="$1" default="${2:-}" value
  if [[ -n "${default}" ]]; then
    printf '%s [%s]: ' "${label}" "${default}" >&2
  else
    printf '%s: ' "${label}" >&2
  fi
  IFS= read -r value || value=''
  printf '%s' "${value:-${default}}"
}

shipping_prompt_yes() {
  local label="$1" default="${2:-n}" value
  value="$(shipping_prompt "${label} (y/n)" "${default}")"
  case "${value}" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

shipping_csv_json() {
  jq -Rn --arg raw "$1" '$raw | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))'
}

shipping_add_interactive_jobs() {
  local proposal="$1" pipeline target driver id job files services source destination repository ref stage command
  [[ -t 0 ]] || die "--interactive requires a terminal." 2

  while shipping_prompt_yes "Add a shipping job?" "n"; do
    pipeline="$(shipping_prompt "Pipeline name" "$(jq -r '.default_pipeline' <<< "${proposal}")")"
    target="$(jq -r --arg pipeline "${pipeline}" '.pipelines[$pipeline].target // empty' <<< "${proposal}")"
    if [[ -z "${target}" ]]; then
      target="$(shipping_prompt "Target id" "${pipeline}")"
      proposal="$(jq -c --arg pipeline "${pipeline}" --arg target "${target}" '
        .targets[$target] //= {transport: "ssh", config_ref: ("ci.deploy." + $target)} |
        .pipelines[$pipeline] //= {description: "User configured shipping pipeline", target: $target, jobs: []}
      ' <<< "${proposal}")"
    fi

    id="$(shipping_prompt "Job id" "")"
    [[ "${id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { warn "Invalid job id; try again."; continue; }
    driver="$(shipping_prompt "Driver (docker.compose/files.sync/git.checkout/script)" "docker.compose")"

    case "${driver}" in
      docker.compose)
        files="$(shipping_prompt "Compose files, comma-separated" "")"
        [[ -n "${files}" ]] || { warn "At least one Compose file is required."; continue; }
        services="$(shipping_prompt "Compose services, comma-separated (blank = driver default)" "")"
        job="$(jq -n --arg id "${id}" --argjson files "$(shipping_csv_json "${files}")" --argjson services "$(shipping_csv_json "${services}")" '{id: $id, uses: "docker.compose", compose_files: $files, project_directory: "."} + (if ($services | length) > 0 then {services: $services} else {} end)')"
        ;;
      files.sync)
        source="$(shipping_prompt "Source path" "")"
        destination="$(shipping_prompt "Destination path" "")"
        [[ -n "${source}" && -n "${destination}" ]] || { warn "Source and destination are required."; continue; }
        job="$(jq -n --arg id "${id}" --arg source "${source}" --arg destination "${destination}" '{id: $id, uses: "files.sync", source: $source, destination: $destination}')"
        ;;
      git.checkout)
        repository="$(shipping_prompt "Git repository" "")"
        ref="$(shipping_prompt "Git ref ({tag} is supported)" "{tag}")"
        destination="$(shipping_prompt "Remote checkout path" "")"
        [[ -n "${repository}" && -n "${destination}" ]] || { warn "Repository and destination are required."; continue; }
        job="$(jq -n --arg id "${id}" --arg repository "${repository}" --arg ref "${ref}" --arg destination "${destination}" '{id: $id, uses: "git.checkout", repository: $repository, ref: $ref, destination: $destination}')"
        ;;
      script)
        stage="$(shipping_prompt "Lifecycle stage (build/publish/transfer/deploy/verify)" "deploy")"
        case "${stage}" in build|publish|transfer|deploy|verify) ;; *) warn "Invalid lifecycle stage."; continue ;; esac
        command="$(shipping_prompt "Command argv, comma-separated" "")"
        [[ -n "${command}" ]] || { warn "Command is required."; continue; }
        job="$(jq -n --arg id "${id}" --arg stage "${stage}" --argjson command "$(shipping_csv_json "${command}")" '{id: $id, uses: "script", stages: {($stage): {run_on: "local", command: $command}}}')"
        ;;
      *) warn "Unknown driver: ${driver}"; continue ;;
    esac

    proposal="$(jq -c --arg pipeline "${pipeline}" --argjson job "${job}" '.pipelines[$pipeline].jobs += [$job]' <<< "${proposal}")"
  done
  printf '%s' "${proposal}"
}

config_file="${OPS_SHIPPING_CONFIG_FILE}"
if [[ -f "${config_file}" && "${REFRESH}" != "true" ]]; then
  shipping_validate_config "${config_file}"
  proposal="$(cat "${config_file}")"
  source_label='existing reviewed config'
else
  proposal="$(shipping_infer_config)"
  source_label='fresh inference'
fi

if [[ "${INTERACTIVE}" == "true" ]]; then
  proposal="$(shipping_add_interactive_jobs "${proposal}")"
  source_label="${source_label} + interactive decisions"
fi

tmp_file="$(mktemp)"
printf '%s\n' "${proposal}" > "${tmp_file}"
shipping_validate_config "${tmp_file}"

if [[ "${JSON}" == "true" ]]; then
  jq . "${tmp_file}"
elif [[ "${APPLY}" != "true" ]]; then
  ops_section "ops setup shipping"
  printf 'Proposal source: %s\n' "${source_label}"
  printf 'Config path:     %s\n\n' "${config_file#${OPS_PROJECT_ROOT}/}"
  jq -r '
    .pipelines | to_entries[] |
    "Pipeline \(.key) -> \(.value.target):", (.value.jobs[] | "  - \(.id): \(.uses)")
  ' "${tmp_file}"
  printf '\n'
  ops_info "Preview only. Use --apply to write the reviewed shipping configuration."
fi

if [[ "${APPLY}" == "true" ]]; then
  ensure_dir "${OPS_PROJECT_CONFIG_DIR}"
  if [[ -f "${config_file}" ]]; then
    ensure_dir "${OPS_PROJECT_HISTORY_DIR}"
    cp "${config_file}" "${OPS_PROJECT_HISTORY_DIR}/shipping.$(ops_timestamp | tr ':' '-').json"
  fi
  jq . "${tmp_file}" > "${config_file}"
  ops_ok "Wrote ${config_file#${OPS_PROJECT_ROOT}/}"
fi

rm -f "${tmp_file}"
