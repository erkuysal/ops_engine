#!/usr/bin/env bash
# Validate schema contracts against representative valid and invalid JSON.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if ! command -v ajv >/dev/null 2>&1; then
  printf 'schema tests: ajv-cli 5.x is required\n' >&2
  printf 'Install it with: npm install --global ajv-cli@5.0.0\n' >&2
  exit 2
fi

validate_ok() {
  local schema="$1" data="$2"
  printf '  valid   %s <- %s\n' "${data#${OPS_REPO_ROOT}/}" "${schema#${OPS_REPO_ROOT}/}"
  ajv validate --spec=draft2020 --strict=false -s "${schema}" -d "${data}" >/dev/null
}

validate_rejected() {
  local schema="$1" data="$2"
  printf '  invalid %s <- %s\n' "${data#${OPS_REPO_ROOT}/}" "${schema#${OPS_REPO_ROOT}/}"
  if ajv validate --spec=draft2020 --strict=false -s "${schema}" -d "${data}" >/dev/null 2>&1; then
    printf 'schema tests: expected fixture to be rejected: %s\n' "${data}" >&2
    return 1
  fi
}

runtime_validate() {
  local project_root="$1"
  OPS_PROJECT_ROOT="${project_root}" \
  OPS_CORE_ROOT="${OPS_REPO_ROOT}/core" \
  OPS_PLAIN=true \
  CI=true \
  OPS_NON_INTERACTIVE=true \
    bash "${OPS_REPO_ROOT}/core/main.sh" validate --plain >/dev/null 2>&1
}

printf 'ops JSON Schema contracts\n'

for schema in "${OPS_REPO_ROOT}"/schemas/*.schema.json; do
  printf '  schema  %s\n' "${schema#${OPS_REPO_ROOT}/}"
  ajv compile --spec=draft2020 --strict=false -s "${schema}" >/dev/null
done

validate_ok "${OPS_REPO_ROOT}/schemas/global-profile.schema.json" \
  "${SCRIPT_DIR}/fixtures/global-profile-valid.json"
validate_ok "${OPS_REPO_ROOT}/schemas/setup.schema.json" \
  "${OPS_REPO_ROOT}/templates/setup.json"
validate_ok "${OPS_REPO_ROOT}/schemas/settings.schema.json" \
  "${OPS_REPO_ROOT}/templates/settings.json"

for profile in "${OPS_REPO_ROOT}"/templates/profiles/*.json; do
  validate_ok "${OPS_REPO_ROOT}/schemas/profile.schema.json" "${profile}"
done

validate_ok "${OPS_REPO_ROOT}/schemas/shipping.schema.json" \
  "${OPS_REPO_ROOT}/tests/fixtures/container-pipeline/.ops.project/config/shipping.json"

for fixture in config-only configured-command container-pipeline; do
  config_dir="${OPS_REPO_ROOT}/tests/fixtures/${fixture}/.ops.project/config"
  validate_ok "${OPS_REPO_ROOT}/schemas/project-config.schema.json" "${config_dir}/project.json"
  validate_ok "${OPS_REPO_ROOT}/schemas/services-config.schema.json" "${config_dir}/services.json"
  validate_ok "${OPS_REPO_ROOT}/schemas/settings-config.schema.json" "${config_dir}/settings.json"
  validate_ok "${OPS_REPO_ROOT}/schemas/profiles-config.schema.json" "${config_dir}/profiles.json"
done
validate_ok "${OPS_REPO_ROOT}/schemas/services-config.schema.json" \
  "${OPS_REPO_ROOT}/tests/fixtures/go-process-group-config/.ops.project/config/services.json"

validate_rejected "${OPS_REPO_ROOT}/schemas/settings.schema.json" \
  "${SCRIPT_DIR}/fixtures/settings-invalid.json"
validate_rejected "${OPS_REPO_ROOT}/schemas/global-profile.schema.json" \
  "${SCRIPT_DIR}/fixtures/global-profile-invalid.json"
validate_rejected "${OPS_REPO_ROOT}/schemas/shipping.schema.json" \
  "${SCRIPT_DIR}/fixtures/shipping-invalid.json"
validate_rejected "${OPS_REPO_ROOT}/schemas/services-config.schema.json" \
  "${OPS_REPO_ROOT}/tests/fixtures/config-invalid/.ops.project/config/services.json"

printf '  runtime valid agreement\n'
runtime_validate "${OPS_REPO_ROOT}/tests/fixtures/config-only"
printf '  runtime invalid agreement\n'
if runtime_validate "${OPS_REPO_ROOT}/tests/fixtures/config-invalid"; then
  printf 'schema tests: runtime validator accepted the invalid config fixture\n' >&2
  exit 1
fi

printf 'schema contracts: passed\n'
