#!/usr/bin/env bash
# .ops/core/lib/setup_check.sh — Read-only drift detection (discovery vs config).

set -euo pipefail
if [[ "${_OPS_CORE_SETUP_CHECK_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_SETUP_CHECK_LOADED=1

# shellcheck source=manifest.sh
source "${OPS_CORE_ROOT}/lib/manifest.sh"

setup_check_load_current_json() {
  require_bins jq
  local services='[]' global_env='[]' config_source="none"

  if project_config_services_exists; then
    services="$(jq -c '.services // []' "${OPS_PROJECT_CONFIG_SERVICES_FILE}")"
    config_source=".ops.project/config/services.json"
  elif manifest_exists; then
    require_bins yq
    services="$(yq e -o=json '.services // []' "${OPS_MANIFEST}" 2>/dev/null || printf '[]')"
    config_source=".ops.yaml"
  fi

  if [[ -f "${OPS_PROJECT_CONFIG_PROJECT_FILE:-}" ]]; then
    global_env="$(jq -c '.global_env_files // []' "${OPS_PROJECT_CONFIG_PROJECT_FILE}" 2>/dev/null || printf '[]')"
  elif manifest_exists; then
    global_env="$(yq e -o=json '.project.global_env_files // []' "${OPS_MANIFEST}" 2>/dev/null || printf '[]')"
  fi

  jq -n \
    --arg source "${config_source}" \
    --argjson services "${services}" \
    --argjson global_env_files "${global_env}" \
    '{config_source: $source, services: $services, global_env_files: $global_env_files}'
}

setup_check_build_report_json() {
  local discovery_json="$1"
  local proposed_setup_json="$2"
  local current_json="$3"
  local cached_discovery_json="${4-}"
  local tmpdir discovery_file proposed_file current_file cached_file

  require_bins jq
  [[ -n "${cached_discovery_json}" ]] || cached_discovery_json='{}'

  tmpdir="$(mktemp -d)"
  discovery_file="${tmpdir}/discovery.json"
  proposed_file="${tmpdir}/proposed.json"
  current_file="${tmpdir}/current.json"
  cached_file="${tmpdir}/cached.json"
  printf '%s' "${discovery_json}" > "${discovery_file}"
  printf '%s' "${proposed_setup_json}" > "${proposed_file}"
  printf '%s' "${current_json}" > "${current_file}"
  printf '%s' "${cached_discovery_json}" > "${cached_file}"

  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --slurpfile discovery "${discovery_file}" \
    --slurpfile proposed_setup "${proposed_file}" \
    --slurpfile current "${current_file}" \
    --slurpfile cached "${cached_file}" \
    -f "${OPS_CORE_ROOT}/lib/setup_check.jq"

  rm -rf "${tmpdir}"
}

setup_check_has_drift() {
  local report_json="$1"
  jq -e '
    (.summary.added // 0) > 0
    or (.summary.removed // 0) > 0
    or (.summary.changed // 0) > 0
    or (.summary.global_env_changed // false)
  ' <<< "${report_json}" >/dev/null 2>&1
}

setup_check_print_report() {
  local report_json="$1"
  local added removed changed global_changed cache_stale config_source

  added="$(jq -r '.summary.added // 0' <<< "${report_json}")"
  removed="$(jq -r '.summary.removed // 0' <<< "${report_json}")"
  changed="$(jq -r '.summary.changed // 0' <<< "${report_json}")"
  global_changed="$(jq -r '.summary.global_env_changed // false' <<< "${report_json}")"
  cache_stale="$(jq -r '.summary.cache_stale // false' <<< "${report_json}")"
  config_source="$(jq -r '.config_source // "none"' <<< "${report_json}")"

  ops_section "ops setup check"
  ops_info "Config source: ${config_source}"
  printf '\n'

  if [[ "${config_source}" == "none" ]]; then
    ops_warn "No project config found. Comparison uses discovery-only proposed services."
    printf '\n'
  fi

  if [[ "${cache_stale}" == "true" ]]; then
    ops_warn "Cached discovery.json differs from fresh scan. Run: ops setup discover --apply"
    printf '\n'
  fi

  printf 'Summary: %s added, %s removed, %s changed' "${added}" "${removed}" "${changed}"
  [[ "${global_changed}" == "true" ]] && printf ', global env files changed'
  printf '\n\n'

  if jq -e '.added | length > 0' <<< "${report_json}" >/dev/null; then
    printf 'Added services (in discovery, not in config):\n'
    jq -r '.added[] | "  + \(.id)  \(.path)  (\(.stack)/\(.role))"' <<< "${report_json}"
    printf '\n'
  fi

  if jq -e '.removed | length > 0' <<< "${report_json}" >/dev/null; then
    printf 'Removed services (in config, not proposed by discovery):\n'
    jq -r '.removed[] | "  - \(.id)  \(.path)  (\(.stack)/\(.role))"' <<< "${report_json}"
    printf '\n'
  fi

  if jq -e '.changed | length > 0' <<< "${report_json}" >/dev/null; then
    printf 'Changed services:\n'
    jq -r '.changed[] | . as $svc | .fields[] | "  \($svc.id).\(.name): \(.current | tostring) -> \(.proposed | tostring)"' <<< "${report_json}"
    printf '\n'
  fi

  if [[ "${global_changed}" == "true" ]]; then
    printf 'Global env files:\n'
    jq -r '.global_env_files | "  current:  \(.current | join(", "))\n  proposed: \(.proposed | join(", "))"' <<< "${report_json}"
    printf '\n'
  fi

  if setup_check_has_drift "${report_json}"; then
    ops_warn "Drift detected. Review changes and run: ops setup --apply"
    return 1
  fi

  ops_ok "No drift detected between discovery and config."
  return 0
}

return 0
