#!/usr/bin/env bash
# .ops/core/lib/manifest_sync.sh — Export/import between .ops.project/config and .ops.yaml

set -euo pipefail
if [[ "${_OPS_CORE_MANIFEST_SYNC_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_MANIFEST_SYNC_LOADED=1

# shellcheck source=manifest.sh
source "${OPS_CORE_ROOT}/lib/manifest.sh"
# shellcheck source=setup.sh
source "${OPS_CORE_ROOT}/lib/setup.sh"
# shellcheck source=backup.sh
source "${OPS_CORE_ROOT}/lib/backup.sh"
# shellcheck source=logger.sh
source "${OPS_CORE_ROOT}/lib/logger.sh"

require_manifest_or_config() {
  if manifest_exists || project_config_services_exists; then
    return 0
  fi
  die "No project ops config found.
  Run:  ops setup --apply
  Or:   ops setup import-yaml --apply (if you have .ops.yaml)" 2
}

# Emit a manifest-shaped JSON document from .ops.project/config (stdout).
manifest_json_from_project_config() {
  require_bins jq yq
  project_config_services_exists || die "Missing ${OPS_PROJECT_CONFIG_SERVICES_FILE}. Run ops setup --apply first." 2

  local project_json='{}' settings_json='{}' services_json='[]' profiles_json='{}' default_profile='local'
  local setup_json='{}' settings_only='{}' ci_json='{}'

  [[ -f "${OPS_PROJECT_CONFIG_PROJECT_FILE}" ]] && project_json="$(cat "${OPS_PROJECT_CONFIG_PROJECT_FILE}")"
  [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]] && settings_json="$(cat "${OPS_PROJECT_CONFIG_SETTINGS_FILE}")"
  [[ -f "${OPS_PROJECT_CONFIG_SERVICES_FILE}" ]] && services_json="$(jq -c '.services // []' "${OPS_PROJECT_CONFIG_SERVICES_FILE}")"
  [[ -f "${OPS_PROJECT_CONFIG_PROFILES_FILE}" ]] && profiles_json="$(cat "${OPS_PROJECT_CONFIG_PROFILES_FILE}")"

  default_profile="$(jq -r '.default_profile // "local"' <<< "${profiles_json}")"
  setup_json="$(jq -c '.setup // {}' <<< "${settings_json}")"
  settings_only="$(jq -c '.settings // {}' <<< "${settings_json}")"
  [[ -f "${OPS_PROJECT_CONFIG_DIR}/ci.json" ]] && ci_json="$(cat "${OPS_PROJECT_CONFIG_DIR}/ci.json")" || ci_json='{}'

  jq -n \
    --argjson version 1 \
    --argjson project "${project_json}" \
    --argjson services "${services_json}" \
    --argjson settings "${settings_only}" \
    --argjson setup "${setup_json}" \
    --argjson profiles "$(jq -c '.profiles // {}' <<< "${profiles_json}")" \
    --argjson ci "${ci_json}" \
    '
      {
        version: $version,
        project: {
          name: ($project.name // "project"),
          global_env_files: ($project.global_env_files // []),
          defaults: ($project.defaults // {env_policy: "dev_file"})
        },
        services: [
          $services[] | {
            id,
            name,
            stack,
            path,
            compose_files: (.compose_files // []),
            env_files: (.env_files // []),
            env_policy: ((.env_policy // "") | if . == "" then "dev_file" else . end),
            env_materialization: ((.env_materialization // "") | if . == "" then "none" else . end),
            env_output_file: (.env_output_file // ""),
            actions: (.actions // {}),
            depends_on: (.depends_on // []),
            healthcheck: (.healthcheck // ""),
            meta: (.meta // {})
          }
          + (if (.runner.kind? // "") == "process_group" then {runner: .runner, build: .build, run: .run}
             elif (.runner.kind? // "") == "compose" then {runner: .runner}
             else {} end)
        ],
        settings: $settings,
        setup: $setup,
        profiles: $profiles,
        ci: (if ($ci | keys | length) > 0 then $ci else null end)
      }
      | if .ci == null then del(.ci) else . end
    '
}

manifest_export_yaml() {
  local target="${1:-${OPS_MANIFEST}}"
  require_bins jq yq

  local json
  json="$(manifest_json_from_project_config)"

  if [[ -f "${target}" ]]; then
    ops_backup_manifest
  fi

  printf '%s\n' "${json}" | yq e -P - > "${target}"
  ops_ok "Exported project config to ${target#${OPS_PROJECT_ROOT}/}"
}

manifest_import_yaml() {
  require_bins jq yq
  manifest_exists || die "No .ops.yaml at ${OPS_MANIFEST} to import." 2

  _ensure_project_base_import() {
    mkdir -p "${OPS_PROJECT_CONFIG_DIR}" "${OPS_PROJECT_GENERATED_DIR}" "${OPS_PROJECT_LOG_DIR}" "${OPS_PROJECT_RUN_DIR}" "${OPS_PROFILES_DIR}"
  }

  _ensure_project_base_import

  local manifest_json
  manifest_json="$(yq e -o=json '.' "${OPS_MANIFEST}")"

  local project_name settings_json setup_json profiles_json default_profile services_wrapped

  project_name="$(jq -r '.project.name // ""' <<< "${manifest_json}")"
  [[ -z "${project_name}" || "${project_name}" == "null" ]] && project_name="$(basename "${OPS_PROJECT_ROOT}")"

  jq -n \
    --argjson version 1 \
    --arg generated_at "$(ops_timestamp)" \
    --arg name "${project_name}" \
    --arg root "${OPS_PROJECT_ROOT}" \
    --arg manifest ".ops.yaml" \
    --argjson project "$(jq -c '.project // {}' <<< "${manifest_json}")" \
    '{
      version: $version,
      generated_at: $generated_at,
      name: $name,
      root: $root,
      compatibility_manifest: $manifest,
      global_env_files: ($project.global_env_files // []),
      defaults: ($project.defaults // {env_policy: "dev_file"})
    }' > "${OPS_PROJECT_CONFIG_DIR}/project.json"

  services_wrapped="$(jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --argjson services "$(jq -c '.services // []' <<< "${manifest_json}")" \
    '{version: 1, generated_at: $generated_at, source: "import_yaml", services: $services}')"
  printf '%s\n' "${services_wrapped}" > "${OPS_PROJECT_CONFIG_SERVICES_FILE}"

  setup_json="$(jq -c '.setup // {}' <<< "${manifest_json}")"
  settings_json="$(jq -c '.settings // {}' <<< "${manifest_json}")"
  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --arg source "import_yaml" \
    --argjson settings "${settings_json}" \
    --argjson setup "${setup_json}" \
    '{version: 1, generated_at: $generated_at, source: $source, settings: $settings, setup: $setup}' \
    > "${OPS_PROJECT_CONFIG_SETTINGS_FILE}"

  default_profile="$(jq -r '.setup.default_profile // "local"' <<< "${manifest_json}")"
  [[ -z "${default_profile}" || "${default_profile}" == "null" ]] && default_profile="local"
  profiles_json="$(jq -c '.profiles // {}' <<< "${manifest_json}")"
  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --arg profile "${default_profile}" \
    --argjson profiles "${profiles_json}" \
    '{version: 1, generated_at: $generated_at, default_profile: $profile, profiles: $profiles}' \
    > "${OPS_PROJECT_CONFIG_PROFILES_FILE}"

  if jq -e '.ci // null | type == "object"' <<< "${manifest_json}" >/dev/null 2>&1; then
    jq -c '.ci' <<< "${manifest_json}" > "${OPS_PROJECT_CONFIG_DIR}/ci.json"
  fi

  ops_ok "Imported .ops.yaml into .ops.project/config/"
}

return 0
