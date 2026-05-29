#!/usr/bin/env bash
# .ops/core/lib/setup.sh — Root .ops.yaml setup/profile accessors.

set -euo pipefail
if [[ "${_OPS_CORE_SETUP_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_SETUP_LOADED=1

OPS_SETUP_FILE="${OPS_MANIFEST}"
OPS_PROJECT_STATE_DIR="${OPS_PROJECT_ROOT}/.ops.project"
OPS_PROJECT_LOG_DIR="${OPS_PROJECT_STATE_DIR}/logs"
OPS_PROJECT_RUN_DIR="${OPS_PROJECT_STATE_DIR}/run"
OPS_PROJECT_GENERATED_DIR="${OPS_PROJECT_STATE_DIR}/generated"
OPS_PROJECT_CONFIG_DIR="${OPS_PROJECT_STATE_DIR}/config"
OPS_PROJECT_HISTORY_DIR="${OPS_PROJECT_STATE_DIR}/.history"
OPS_PROFILES_DIR="${OPS_PROJECT_STATE_DIR}/profiles"
OPS_PROJECT_SETUP_GENERATED_FILE="${OPS_PROJECT_GENERATED_DIR}/setup.json"
OPS_PROJECT_SETUP_GENERATED_LEGACY_FILE="${OPS_PROJECT_GENERATED_DIR}/setup.yaml"
OPS_PROJECT_CONFIG_SETTINGS_FILE="${OPS_PROJECT_CONFIG_DIR}/settings.json"
OPS_PROJECT_CONFIG_PROFILES_FILE="${OPS_PROJECT_CONFIG_DIR}/profiles.json"
export OPS_SETUP_FILE OPS_PROJECT_STATE_DIR OPS_PROJECT_LOG_DIR OPS_PROJECT_RUN_DIR OPS_PROJECT_GENERATED_DIR OPS_PROJECT_CONFIG_DIR OPS_PROJECT_HISTORY_DIR OPS_PROFILES_DIR OPS_PROJECT_CONFIG_SETTINGS_FILE OPS_PROJECT_CONFIG_PROFILES_FILE

setup_exists() {
  [[ -f "${OPS_SETUP_FILE}" ]] || [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]
}

setup_profile_file() {
  local profile="$1"
  printf '%s/%s.json' "${OPS_PROFILES_DIR}" "${profile}"
}

setup_generated_exists() {
  [[ -f "${OPS_PROJECT_SETUP_GENERATED_FILE}" || -f "${OPS_PROJECT_SETUP_GENERATED_LEGACY_FILE}" ]]
}

_setup_generated_get() {
  local expr="${1:?_setup_generated_get: jq expression required}"

  if [[ -f "${OPS_PROJECT_SETUP_GENERATED_FILE}" ]]; then
    require_bins jq
    jq -r "${expr} // \"\"" "${OPS_PROJECT_SETUP_GENERATED_FILE}" 2>/dev/null || true
    return 0
  fi

  if [[ -f "${OPS_PROJECT_SETUP_GENERATED_LEGACY_FILE}" ]]; then
    require_bins yq
    yq e "${expr} // \"\"" "${OPS_PROJECT_SETUP_GENERATED_LEGACY_FILE}" 2>/dev/null || true
    return 0
  fi

  printf ''
}

setup_default_profile() {
  if [[ -f "${OPS_PROJECT_CONFIG_PROFILES_FILE}" ]]; then
    require_bins jq
    local profile
    profile="$(jq -r '.default_profile // ""' "${OPS_PROJECT_CONFIG_PROFILES_FILE}" 2>/dev/null || true)"
    [[ -n "${profile}" && "${profile}" != "null" ]] && { printf '%s' "${profile}"; return 0; }
  fi
  if setup_exists; then
    local profile
    profile="$(yq e '.setup.default_profile // ""' "${OPS_SETUP_FILE}" 2>/dev/null || true)"
    [[ -n "${profile}" && "${profile}" != "null" ]] && printf '%s' "${profile}" || printf 'local'
  else
    printf 'local'
  fi
}

setup_validate() {
  require_bins jq yq
  if [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]; then
    jq -e '.setup // {} | type == "object"' "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" >/dev/null
    return $?
  fi
  [[ -f "${OPS_SETUP_FILE}" ]] || return 0
  yq e '.setup // {}' "${OPS_SETUP_FILE}" >/dev/null
}

setup_profile_validate() {
  local profile="$1"
  require_bins jq yq
  if [[ -f "${OPS_PROJECT_CONFIG_PROFILES_FILE}" ]]; then
    jq -e --arg profile "${profile}" '.profiles[$profile] // {} | type == "object"' \
      "${OPS_PROJECT_CONFIG_PROFILES_FILE}" >/dev/null
    return $?
  fi
  [[ -f "${OPS_SETUP_FILE}" ]] || return 0
  yq e ".profiles.${profile} // {}" "${OPS_SETUP_FILE}" >/dev/null
}

setup_get() {
  local expr="${1:?setup_get: jq expression required}"
  local default="${2:-}"
  if [[ -f "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" ]]; then
    require_bins jq
    local config_value
    config_value="$(jq -r ".setup${expr} // \"\"" "${OPS_PROJECT_CONFIG_SETTINGS_FILE}" 2>/dev/null || true)"
    [[ -n "${config_value}" && "${config_value}" != "null" ]] && { printf '%s' "${config_value}"; return 0; }
  fi
  if ! setup_exists; then
    printf '%s' "${default}"
    return 0
  fi
  require_bins yq
  local value
  value="$(yq e ".setup${expr} // \"\"" "${OPS_SETUP_FILE}" 2>/dev/null || true)"
  [[ -n "${value}" && "${value}" != "null" ]] && printf '%s' "${value}" || printf '%s' "${default}"
}

setup_service_get() {
  local service_id="${1:?setup_service_get: service id required}"
  local field="${2:?setup_service_get: field required}"
  local default="${3:-}"
  setup_get ".services[\"${service_id}\"].${field}" "${default}"
}

setup_stack_default_command() {
  local stack="${1:-}" action="${2:-start}"
  case "${stack}:${action}" in
    django:start) printf 'python -u manage.py runserver 0.0.0.0:8000' ;;
    django:test) printf 'python manage.py test' ;;
    node:start) printf 'npm start' ;;
    node:build) printf 'npm run build' ;;
    node:test) printf 'npm test' ;;
    node:lint) printf 'npm run lint' ;;
    go:start) printf 'go run main.go' ;;
    go:build) printf 'go build -o app' ;;
    go:test) printf 'go test ./...' ;;
    elixir-phoenix:start) printf 'mix phx.server' ;;
    elixir-phoenix:test) printf 'mix test' ;;
    elixir-phoenix:build) printf 'mix release' ;;
    docker:start) printf 'docker compose up -d' ;;
    docker:stop) printf 'docker compose down' ;;
    docker:logs) printf 'docker compose logs -f' ;;
    docker:status) printf 'docker compose ps --services --filter status=running' ;;
    *) printf '' ;;
  esac
}

setup_service_start_command() {
  local service_id="${1:?setup_service_start_command: service id required}"
  local command runner_kind stack

  if type manifest_get_service_field >/dev/null 2>&1; then
    runner_kind="$(manifest_get_service_field "${service_id}" "runner.kind" 2>/dev/null || true)"
  else
    runner_kind="$(yq e ".services[] | select(.id == \"${service_id}\") | .runner.kind // \"\"" "${OPS_MANIFEST}" 2>/dev/null || true)"
  fi
  if [[ "${runner_kind}" == "process_group" ]]; then
    printf ''
    return 0
  fi

  if setup_generated_exists; then
    command="$(_setup_generated_get ".services.\"${service_id}\".command")"
    [[ -n "${command}" && "${command}" != "null" ]] && { printf '%s' "${command}"; return 0; }
  fi

  command="$(setup_service_get "${service_id}" command "")"
  if [[ -n "${command}" && "${command}" != "null" ]]; then
    printf '%s' "${command}"
    return 0
  fi

  stack="$(manifest_get_service_field "${service_id}" stack 2>/dev/null || true)"
  printf '%s' "$(setup_stack_default_command "${stack}" start)"
}

setup_service_django_conda_env() {
  local service_id="${1:?setup_service_django_conda_env: service id required}"
  local env_name=""

  if setup_generated_exists; then
    env_name="$(_setup_generated_get ".services.\"${service_id}\".django.conda_env")"
    if [[ -n "${env_name}" && "${env_name}" != "null" ]]; then
      printf '%s' "${env_name}"
      return 0
    fi
  fi

  env_name="$(setup_service_get "${service_id}" 'django.conda_env' '')"
  if [[ -n "${env_name}" && "${env_name}" != "null" ]]; then
    printf '%s' "${env_name}"
    return 0
  fi

  local manager
  manager="$(setup_get '.runtimes.python.manager' '')"
  if [[ "${manager}" == "conda" ]]; then
    env_name="$(setup_get '.runtimes.python.env' '')"
    if [[ -n "${env_name}" && "${env_name}" != "null" ]]; then
      printf '%s' "${env_name}"
      return 0
    fi
  fi

  printf ''
}

setup_profile_get() {
  local profile="${1:?setup_profile_get: profile required}"
  local expr="${2:?setup_profile_get: jq expression required}"
  local default="${3:-}"
  if [[ -f "${OPS_PROJECT_CONFIG_PROFILES_FILE}" ]]; then
    require_bins jq
    local config_value
    config_value="$(jq -r ".profiles.\"${profile}\"${expr} // \"\"" "${OPS_PROJECT_CONFIG_PROFILES_FILE}" 2>/dev/null || true)"
    [[ -n "${config_value}" && "${config_value}" != "null" ]] && { printf '%s' "${config_value}"; return 0; }
  fi
  if ! setup_exists; then
    printf '%s' "${default}"
    return 0
  fi
  require_bins yq
  local value
  value="$(yq e ".profiles.${profile}${expr} // \"\"" "${OPS_SETUP_FILE}" 2>/dev/null || true)"
  [[ -n "${value}" && "${value}" != "null" ]] && printf '%s' "${value}" || printf '%s' "${default}"
}

setup_runtime_python_activation() {
  local manager env_name
  manager="$(setup_get '.runtimes.python.manager' '')"
  env_name="$(setup_get '.runtimes.python.env' '')"
  if [[ "${manager}" == "conda" && -n "${env_name}" ]]; then
    printf 'conda activate %s' "${env_name}"
  elif [[ -f "${OPS_PROJECT_ROOT}/.venv/bin/activate" ]]; then
    printf 'source .venv/bin/activate'
  elif [[ -f "${OPS_PROJECT_ROOT}/venv/bin/activate" ]]; then
    printf 'source venv/bin/activate'
  else
    printf 'system python from PATH'
  fi
}
