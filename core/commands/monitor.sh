#!/usr/bin/env bash
# .ops/core/commands/monitor.sh — Lightweight service/infra monitoring checks.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/setup.sh"
source "${_SELF_DIR}/../lib/interactive.sh"

SUBCMD="${1:-status}"
case "${SUBCMD}" in
  status|test|hosts|doctor|credentials|env|setup|postgres|help|--help|-h) shift || true ;;
  *) SUBCMD="status" ;;
esac

JSON=false
STRICT=false
TARGET=""
TIMEOUT_SECONDS=2
PROBE_PORT=""
APPLY=false
INTERACTIVE=false
ADD_POSTGRES=false
ADD_REDIS=false
TARGET_HOST_OVERRIDES=()
POSTGRES_ACTION=""
MONITOR_CONFIG="${OPS_PROJECT_CONFIG_DIR}/monitoring.json"
INFRA_ENV_REL=".ops.project/secrets/infra.env"
INFRA_ENV_FILE="${OPS_PROJECT_ROOT}/${INFRA_ENV_REL}"
MONITOR_POSTGRES_HOST="127.0.0.1"
MONITOR_POSTGRES_PORT="5432"
MONITOR_POSTGRES_DB="postgres"
MONITOR_POSTGRES_USER="postgres"
MONITOR_POSTGRES_PASSWORD=""
MONITOR_POSTGRES_DB_ENV="POSTGRES_DB"
MONITOR_POSTGRES_USER_ENV="POSTGRES_USER"
MONITOR_POSTGRES_PASSWORD_ENV="POSTGRES_PASSWORD"
MONITOR_REDIS_HOST="127.0.0.1"
MONITOR_REDIS_PORT="6379"
MONITOR_REDIS_DB="0"
MONITOR_REDIS_PASSWORD=""
MONITOR_REDIS_DB_ENV="REDIS_DB"
MONITOR_REDIS_PASSWORD_ENV="REDIS_PASSWORD"

_usage_monitor() {
  cat <<'EOF'
Usage: ops monitor status [--json] [--target ID] [--timeout=SECONDS]
       ops monitor test [--json] [--target ID] [--timeout=SECONDS] [--strict]
       ops monitor hosts --port=PORT [--json] [--timeout=SECONDS]
       ops monitor setup [--interactive] [--postgres] [--redis] [options] [--apply]
       ops monitor postgres info [--json]
       ops monitor postgres databases [--json]
       ops monitor postgres users [--json]
       ops monitor doctor
       ops monitor credentials [--json]

Reads derived service targets plus optional:
  .ops.project/config/monitoring.json

Supported target kinds:
  http, tcp, postgres, redis

Postgres/Redis secrets are stored locally in:
  .ops.project/secrets/infra.env

Setup options:
  --postgres-host=HOST        --postgres-port=PORT
  --postgres-db=NAME          --postgres-user=USER
  --postgres-password=VALUE   Local dev convenience; may be stored in shell history
  --postgres-no-password      Clear local Postgres password value
  --postgres-db-env=NAME      --postgres-user-env=NAME
  --postgres-password-env=NAME
  --redis-host=HOST           --redis-port=PORT
  --redis-db=INDEX            --redis-db-env=NAME
  --redis-password=VALUE      Local dev convenience; may be stored in shell history
  --redis-no-password         Clear local Redis password value
  --redis-password-env=NAME
  --target-host=ID=HOST       Override a generated/configured target host
  --service-host=SERVICE=HOST Override SERVICE.tcp host
EOF
}

if [[ "${SUBCMD}" == "postgres" ]]; then
  if [[ -z "${1:-}" || "${1:-}" == --* ]]; then
    POSTGRES_ACTION="info"
  else
    POSTGRES_ACTION="${1}"
    case "${POSTGRES_ACTION}" in
      info|databases|users|help|-h) shift || true ;;
      *) die "Unknown monitor postgres subcommand: ${POSTGRES_ACTION}" 2 ;;
    esac
  fi
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=true ;;
    --strict) STRICT=true ;;
    --apply) APPLY=true ;;
    --interactive) INTERACTIVE=true ;;
    --postgres) ADD_POSTGRES=true ;;
    --redis) ADD_REDIS=true ;;
    --postgres-host=*) ADD_POSTGRES=true; MONITOR_POSTGRES_HOST="${1#*=}" ;;
    --postgres-port=*) ADD_POSTGRES=true; MONITOR_POSTGRES_PORT="${1#*=}" ;;
    --postgres-db=*) ADD_POSTGRES=true; MONITOR_POSTGRES_DB="${1#*=}" ;;
    --postgres-user=*) ADD_POSTGRES=true; MONITOR_POSTGRES_USER="${1#*=}" ;;
    --postgres-password=*) ADD_POSTGRES=true; MONITOR_POSTGRES_PASSWORD="${1#*=}" ;;
    --postgres-no-password) ADD_POSTGRES=true; MONITOR_POSTGRES_PASSWORD="" ;;
    --postgres-db-env=*) ADD_POSTGRES=true; MONITOR_POSTGRES_DB_ENV="${1#*=}" ;;
    --postgres-user-env=*) ADD_POSTGRES=true; MONITOR_POSTGRES_USER_ENV="${1#*=}" ;;
    --postgres-password-env=*) ADD_POSTGRES=true; MONITOR_POSTGRES_PASSWORD_ENV="${1#*=}" ;;
    --redis-host=*) ADD_REDIS=true; MONITOR_REDIS_HOST="${1#*=}" ;;
    --redis-port=*) ADD_REDIS=true; MONITOR_REDIS_PORT="${1#*=}" ;;
    --redis-db=*) ADD_REDIS=true; MONITOR_REDIS_DB="${1#*=}" ;;
    --redis-password=*) ADD_REDIS=true; MONITOR_REDIS_PASSWORD="${1#*=}" ;;
    --redis-no-password) ADD_REDIS=true; MONITOR_REDIS_PASSWORD="" ;;
    --redis-db-env=*) ADD_REDIS=true; MONITOR_REDIS_DB_ENV="${1#*=}" ;;
    --redis-password-env=*) ADD_REDIS=true; MONITOR_REDIS_PASSWORD_ENV="${1#*=}" ;;
    --target-host=*) TARGET_HOST_OVERRIDES+=("${1#*=}") ;;
    --service-host=*)
      _monitor_service_host="${1#*=}"
      TARGET_HOST_OVERRIDES+=("${_monitor_service_host%%=*}.tcp=${_monitor_service_host#*=}")
      ;;
    --target=*) TARGET="${1#*=}" ;;
    --target)
      die "--target requires --target=ID form" 2
      ;;
    --port=*) PROBE_PORT="${1#*=}" ;;
    --port)
      die "--port requires --port=PORT form" 2
      ;;
    --timeout=*) TIMEOUT_SECONDS="${1#*=}" ;;
    --timeout)
      die "--timeout requires --timeout=SECONDS form" 2
      ;;
    --help|-h) SUBCMD="help" ;;
    --*) die "Unknown monitor flag: $1" 2 ;;
    *) die "Unexpected monitor argument: $1" 2 ;;
  esac
  shift
done

case "${SUBCMD}" in
  help|--help|-h)
    _usage_monitor
    exit 0
    ;;
esac

_tool_status() {
  local name="$1"
  if command -v "${name}" >/dev/null 2>&1; then
    printf 'ok:%s' "$(command -v "${name}")"
  else
    printf 'missing:'
  fi
}

_monitor_gitignore() {
  local file="${OPS_PROJECT_STATE_DIR}/.gitignore"
  ensure_dir "${OPS_PROJECT_STATE_DIR}"
  if [[ ! -f "${file}" ]]; then
    {
      printf '# Generated by ops. .ops.project is local project state.\n'
      printf 'secrets/\n'
      printf 'logs/\n'
      printf 'run/\n'
    } > "${file}"
    ops_ok "Wrote ${file#${OPS_PROJECT_ROOT}/}"
  elif ! grep -qx 'secrets/' "${file}" 2>/dev/null; then
    printf 'secrets/\n' >> "${file}"
    ops_ok "Updated ${file#${OPS_PROJECT_ROOT}/}"
  fi
}

_prompt_monitor_value() {
  local label="$1" default="${2:-}"
  if [[ "${INTERACTIVE}" != "true" ]]; then
    printf '%s' "${default}"
    return 0
  fi
  interactive_prompt "${label}" "${default}"
}

_prompt_monitor_port() {
  local label="$1" default="${2:-0}"
  if [[ "${INTERACTIVE}" != "true" ]]; then
    printf '%s' "${default}"
    return 0
  fi
  interactive_port_prompt "${label}" "${default}"
}

_prompt_monitor_secret() {
  local label="$1"
  if [[ "${INTERACTIVE}" != "true" ]]; then
    printf ''
    return 0
  fi
  interactive_secret_prompt "${label}" "empty"
}

_monitor_interactive_select_targets() {
  [[ "${INTERACTIVE}" == "true" ]] || return 0
  if [[ "${ADD_POSTGRES}" == "true" || "${ADD_REDIS}" == "true" ]]; then
    return 0
  fi
  interactive_banner "monitor setup"
  if interactive_confirm "Configure Postgres monitor target?" y; then
    ADD_POSTGRES=true
  fi
  if interactive_confirm "Configure Redis monitor target?" y; then
    ADD_REDIS=true
  fi
}

_monitor_env_template() {
  cat <<EOF
# Local ops infra secrets.
# This file is local-only. Do not commit it.

POSTGRES_HOST=${MONITOR_POSTGRES_HOST}
POSTGRES_PORT=${MONITOR_POSTGRES_PORT}
${MONITOR_POSTGRES_DB_ENV}=${MONITOR_POSTGRES_DB}
${MONITOR_POSTGRES_USER_ENV}=${MONITOR_POSTGRES_USER}
${MONITOR_POSTGRES_PASSWORD_ENV}=${MONITOR_POSTGRES_PASSWORD}

REDIS_HOST=${MONITOR_REDIS_HOST}
REDIS_PORT=${MONITOR_REDIS_PORT}
${MONITOR_REDIS_DB_ENV}=${MONITOR_REDIS_DB}
${MONITOR_REDIS_PASSWORD_ENV}=${MONITOR_REDIS_PASSWORD}
EOF
}

_monitor_env_upsert() {
  local key="$1" value="${2:-}" tmp
  [[ -n "${key}" && "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 0
  ensure_dir "$(dirname "${INFRA_ENV_FILE}")"
  if [[ ! -f "${INFRA_ENV_FILE}" ]]; then
    {
      printf '# Local ops infra secrets.\n'
      printf '# This file is local-only. Do not commit it.\n\n'
    } > "${INFRA_ENV_FILE}"
    chmod 600 "${INFRA_ENV_FILE}" 2>/dev/null || true
  fi

  tmp="$(mktemp)"
  awk -v key="${key}" -v value="${value}" '
    BEGIN { done = 0 }
    $0 ~ "^" key "=" {
      print key "=" value
      done = 1
      next
    }
    { print }
    END {
      if (done == 0) {
        print key "=" value
      }
    }
  ' "${INFRA_ENV_FILE}" > "${tmp}"
  mv "${tmp}" "${INFRA_ENV_FILE}"
}

_write_monitor_env_template() {
  ensure_dir "$(dirname "${INFRA_ENV_FILE}")"
  if [[ ! -f "${INFRA_ENV_FILE}" ]]; then
    _monitor_env_template > "${INFRA_ENV_FILE}"
    chmod 600 "${INFRA_ENV_FILE}" 2>/dev/null || true
    _monitor_gitignore
    ops_ok "Created ${INFRA_ENV_REL}"
  else
    _monitor_gitignore
    if [[ "${ADD_POSTGRES}" == "true" ]]; then
      _monitor_env_upsert "POSTGRES_HOST" "${MONITOR_POSTGRES_HOST}"
      _monitor_env_upsert "POSTGRES_PORT" "${MONITOR_POSTGRES_PORT}"
      _monitor_env_upsert "${MONITOR_POSTGRES_DB_ENV}" "${MONITOR_POSTGRES_DB}"
      _monitor_env_upsert "${MONITOR_POSTGRES_USER_ENV}" "${MONITOR_POSTGRES_USER}"
      _monitor_env_upsert "${MONITOR_POSTGRES_PASSWORD_ENV}" "${MONITOR_POSTGRES_PASSWORD}"
    fi
    if [[ "${ADD_REDIS}" == "true" ]]; then
      _monitor_env_upsert "REDIS_HOST" "${MONITOR_REDIS_HOST}"
      _monitor_env_upsert "REDIS_PORT" "${MONITOR_REDIS_PORT}"
      _monitor_env_upsert "${MONITOR_REDIS_DB_ENV}" "${MONITOR_REDIS_DB}"
      _monitor_env_upsert "${MONITOR_REDIS_PASSWORD_ENV}" "${MONITOR_REDIS_PASSWORD}"
    fi
    ops_ok "Updated ${INFRA_ENV_REL}"
  fi
}

_load_infra_env() {
  local line key value
  [[ -f "${INFRA_ENV_FILE}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    line="${line#export }"
    [[ "${line}" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ "${value}" == \"*\" ]]; then
      value="${value#\"}"; value="${value%\"}"
    elif [[ "${value}" == \'*\' ]]; then
      value="${value#\'}"; value="${value%\'}"
    fi
    if [[ -z "$(printenv "${key}" 2>/dev/null || true)" ]]; then
      export "${key}=${value}"
    fi
  done < "${INFRA_ENV_FILE}"
}

_run_doctor() {
  ops_section "ops monitor doctor"
  local item status path
  for item in jq curl timeout pg_isready redis-cli; do
    status="$(_tool_status "${item}")"
    path="${status#*:}"
    status="${status%%:*}"
    if [[ "${status}" == "ok" ]]; then
      ops_ok "${item}: ${path}"
    else
      case "${item}" in
        pg_isready) ops_warn "${item}: missing (needed only for postgres targets)" ;;
        redis-cli) ops_warn "${item}: missing (needed only for redis targets)" ;;
        *) ops_warn "${item}: missing" ;;
      esac
    fi
  done
  if [[ -f "${MONITOR_CONFIG}" ]]; then
    ops_ok "monitor config: ${MONITOR_CONFIG#${OPS_PROJECT_ROOT}/}"
  else
    ops_info "monitor config: optional file not found (${MONITOR_CONFIG#${OPS_PROJECT_ROOT}/})"
  fi
  if [[ -f "${INFRA_ENV_FILE}" ]]; then
    ops_ok "infra env: ${INFRA_ENV_REL}"
  else
    ops_info "infra env: optional file not found (${INFRA_ENV_REL})"
  fi
}

_credential_status_json() {
  local targets target results='[]'
  _load_infra_env
  targets="$(_targets_json)"
  while IFS= read -r target; do
    [[ -n "${target}" ]] || continue
    local id kind db_env user_env password_env item='[]'
    id="$(jq -r '.id // ""' <<< "${target}")"
    kind="$(jq -r '.kind // ""' <<< "${target}")"
    case "${kind}" in
      postgres|redis) ;;
      *) continue ;;
    esac
    db_env="$(jq -r '.db_env // ""' <<< "${target}")"
    user_env="$(jq -r '.user_env // ""' <<< "${target}")"
    password_env="$(jq -r '.password_env // ""' <<< "${target}")"
    for env_name in "${db_env}" "${user_env}" "${password_env}"; do
      [[ -n "${env_name}" && "${env_name}" != "null" ]] || continue
      item="$(jq -c \
        --arg name "${env_name}" \
        --arg present "$(if [[ -n "$(_env_ref_value "${env_name}")" ]]; then printf true; else printf false; fi)" \
        '. + [{name: $name, present: ($present == "true")}]' <<< "${item}")"
    done
    results="$(jq -c \
      --arg id "${id}" \
      --arg kind "${kind}" \
      --argjson env "${item}" \
      '. + [{id: $id, kind: $kind, env: $env}]' <<< "${results}")"
  done < <(jq -c '.[]' <<< "${targets}")
  jq -n --arg env_file "${INFRA_ENV_REL}" --argjson targets "${results}" \
    '{env_file: $env_file, targets: $targets}'
}

_run_credentials() {
  require_bins jq
  local report missing
  report="$(_credential_status_json)"
  if [[ "${JSON}" == "true" ]]; then
    jq '.' <<< "${report}"
    return 0
  fi

  ops_section "ops monitor credentials"
  if [[ -f "${INFRA_ENV_FILE}" ]]; then
    ops_ok "infra env: ${INFRA_ENV_REL}"
  else
    ops_warn "infra env missing: ${INFRA_ENV_REL}"
  fi

  if [[ "$(jq '.targets | length' <<< "${report}")" == "0" ]]; then
    ops_info "No Postgres/Redis monitor targets found."
    return 0
  fi

  printf '  %-24s %-10s %-24s %s\n' "TARGET" "KIND" "ENV" "STATUS"
  jq -r '.targets[] | . as $target | .env[] | [$target.id, $target.kind, .name, (if .present then "set" else "missing/empty" end)] | @tsv' <<< "${report}" |
    while IFS=$'\t' read -r id kind env_name status; do
      printf '  %-24s %-10s %-24s %s\n' "${id}" "${kind}" "${env_name}" "${status}"
    done

  missing="$(jq '[.targets[].env[] | select(.present == false)] | length' <<< "${report}")"
  if [[ "${missing}" != "0" ]]; then
    ops_warn "${missing} referenced monitor env value(s) missing or empty."
  else
    ops_ok "All referenced monitor env values are set."
  fi
}

_config_targets_json() {
  if [[ -f "${MONITOR_CONFIG}" ]]; then
    jq -c '.targets // []' "${MONITOR_CONFIG}" 2>/dev/null || printf '[]'
  else
    printf '[]'
  fi
}

_service_setup_port() {
  local svc="$1"
  local port=""
  if project_config_services_exists; then
    require_bins jq
    port="$(jq -r --arg id "${svc}" '.services[]? | select(.id == $id) | .setup.port // ""' \
      "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || true)"
  fi
  if [[ -z "${port}" || "${port}" == "null" ]]; then
    port="$(setup_service_get "${svc}" port "0" 2>/dev/null || printf '0')"
  fi
  [[ -n "${port}" && "${port}" != "null" ]] && printf '%s' "${port}" || printf '0'
}

_service_targets_json() {
  require_manifest_or_config
  require_bins jq

  local targets='[]' svc health port
  while IFS= read -r svc; do
    [[ -z "${svc}" || "${svc}" == "null" ]] && continue
    health="$(manifest_get_service_field "${svc}" healthcheck 2>/dev/null || true)"
    port="$(_service_setup_port "${svc}")"

    if [[ -n "${health}" && "${health}" != "null" ]]; then
      targets="$(jq -c \
        --arg id "${svc}.health" \
        --arg service "${svc}" \
        --arg url "${health}" \
        '. + [{id: $id, service: $service, kind: "http", url: $url, source: "service.healthcheck"}]' \
        <<< "${targets}")"
    fi

    if [[ "${port}" =~ ^[0-9]+$ && "${port}" != "0" ]]; then
      targets="$(jq -c \
        --arg id "${svc}.tcp" \
        --arg service "${svc}" \
        --arg port "${port}" \
        '. + [{id: $id, service: $service, kind: "tcp", host: "127.0.0.1", port: ($port | tonumber), source: "service.port"}]' \
        <<< "${targets}")"
    fi
  done < <(manifest_list_services)

  printf '%s' "${targets}"
}

_apply_target_host_overrides_json() {
  local targets_json="$1" override id host exists
  for override in "${TARGET_HOST_OVERRIDES[@]+"${TARGET_HOST_OVERRIDES[@]}"}"; do
    [[ -n "${override}" ]] || continue
    [[ "${override}" == *=* ]] || die "Invalid --target-host/--service-host value: ${override}. Expected id=host." 2
    id="${override%%=*}"
    host="${override#*=}"
    [[ -n "${id}" && -n "${host}" ]] || die "Invalid --target-host/--service-host value: ${override}. Expected id=host." 2
    [[ "${host}" != --* && "${host}" != *[[:space:]]* ]] || die "Invalid host override for ${id}: ${host}" 2
    exists="$(jq -r --arg id "${id}" '[.[] | select(.id == $id)] | length' <<< "${targets_json}")"
    [[ "${exists}" != "0" ]] || die "Cannot override host for unknown monitor target: ${id}" 2
    targets_json="$(jq -c --arg id "${id}" --arg host "${host}" '
      map(if .id == $id then (.host = $host | .source = ((.source // "monitoring.config") + "+host_override")) else . end)
    ' <<< "${targets_json}")"
  done
  printf '%s' "${targets_json}"
}

_validate_target_host_override_args() {
  local override id host
  for override in "${TARGET_HOST_OVERRIDES[@]+"${TARGET_HOST_OVERRIDES[@]}"}"; do
    [[ -n "${override}" ]] || continue
    [[ "${override}" == *=* ]] || die "Invalid --target-host/--service-host value: ${override}. Expected id=host." 2
    id="${override%%=*}"
    host="${override#*=}"
    [[ -n "${id}" && -n "${host}" ]] || die "Invalid --target-host/--service-host value: ${override}. Expected id=host." 2
    [[ "${host}" != --* && "${host}" != *[[:space:]]* ]] || die "Invalid host override for ${id}: ${host}" 2
  done
}

_targets_json() {
  local derived configured
  derived="$(_service_targets_json)"
  configured="$(_config_targets_json)"
  jq -c -n --argjson derived "${derived}" --argjson configured "${configured}" '
    reduce ($derived + $configured)[] as $item ([]; map(select(.id != $item.id)) + [$item])
  '
}

_monitor_config_json() {
  require_bins jq
  local targets
  targets="$(_service_targets_json)"

  if [[ "${ADD_POSTGRES}" == "true" ]]; then
    local pg_host pg_port pg_db pg_user
    pg_host="$(_prompt_monitor_value "Postgres host" "${MONITOR_POSTGRES_HOST}")"
    pg_port="$(_prompt_monitor_port "Postgres port" "${MONITOR_POSTGRES_PORT}")"
    pg_db="$(_prompt_monitor_value "Postgres database" "${MONITOR_POSTGRES_DB}")"
    pg_user="$(_prompt_monitor_value "Postgres user" "${MONITOR_POSTGRES_USER}")"
    if [[ "${INTERACTIVE}" == "true" ]]; then
      MONITOR_POSTGRES_PASSWORD="$(_prompt_monitor_secret "Postgres password (local only; empty for none)")"
    fi
    [[ "${pg_port}" =~ ^[0-9]+$ ]] || pg_port="5432"
    MONITOR_POSTGRES_HOST="${pg_host}"
    MONITOR_POSTGRES_PORT="${pg_port}"
    MONITOR_POSTGRES_DB="${pg_db}"
    MONITOR_POSTGRES_USER="${pg_user}"
    targets="$(jq -c \
      --arg host "${pg_host}" \
      --arg port "${pg_port}" \
      --arg db_env "${MONITOR_POSTGRES_DB_ENV}" \
      --arg user_env "${MONITOR_POSTGRES_USER_ENV}" \
      --arg password_env "${MONITOR_POSTGRES_PASSWORD_ENV}" \
      '. + [{
        id: "postgres.local",
        kind: "postgres",
        host: $host,
        port: ($port | tonumber),
        db_env: $db_env,
        user_env: $user_env,
        password_env: $password_env,
        source: "monitor.setup"
      }]' <<< "${targets}")"
  fi

  if [[ "${ADD_REDIS}" == "true" ]]; then
    local redis_host redis_port redis_db
    redis_host="$(_prompt_monitor_value "Redis host" "${MONITOR_REDIS_HOST}")"
    redis_port="$(_prompt_monitor_port "Redis port" "${MONITOR_REDIS_PORT}")"
    redis_db="$(_prompt_monitor_value "Redis database/index" "${MONITOR_REDIS_DB}")"
    if [[ "${INTERACTIVE}" == "true" ]]; then
      MONITOR_REDIS_PASSWORD="$(_prompt_monitor_secret "Redis password (local only; empty for none)")"
    fi
    [[ "${redis_port}" =~ ^[0-9]+$ ]] || redis_port="6379"
    [[ "${redis_db}" =~ ^[0-9]+$ ]] || redis_db="0"
    MONITOR_REDIS_HOST="${redis_host}"
    MONITOR_REDIS_PORT="${redis_port}"
    MONITOR_REDIS_DB="${redis_db}"
    targets="$(jq -c \
      --arg host "${redis_host}" \
      --arg port "${redis_port}" \
      --arg db_env "${MONITOR_REDIS_DB_ENV}" \
      --arg password_env "${MONITOR_REDIS_PASSWORD_ENV}" \
      '. + [{
        id: "redis.local",
        kind: "redis",
        host: $host,
        port: ($port | tonumber),
        db_env: $db_env,
        password_env: $password_env,
        source: "monitor.setup"
      }]' <<< "${targets}")"
  fi

  targets="$(_apply_target_host_overrides_json "${targets}")"

  jq -n \
    --argjson version 1 \
    --arg generated_at "$(ops_timestamp)" \
    --arg source "ops_monitor_setup" \
    --arg env_file "${INFRA_ENV_REL}" \
    --argjson targets "${targets}" \
    '{
      version: $version,
      generated_at: $generated_at,
      source: $source,
      env_file: $env_file,
      targets: $targets
    }'
}

_run_setup() {
  require_manifest_or_config
  local config_json
  _monitor_interactive_select_targets
  _validate_target_host_override_args
  config_json="$(_monitor_config_json)"

  if [[ "${APPLY}" == "true" ]]; then
    ensure_dir "$(dirname "${MONITOR_CONFIG}")"
    printf '%s\n' "${config_json}" > "${MONITOR_CONFIG}"
    if [[ "${ADD_POSTGRES}" == "true" || "${ADD_REDIS}" == "true" ]]; then
      _write_monitor_env_template
    fi
    if [[ "${JSON}" != "true" ]]; then
      ops_section "ops monitor setup"
      ops_ok "Wrote ${MONITOR_CONFIG#${OPS_PROJECT_ROOT}/}"
    fi
  elif [[ "${JSON}" != "true" ]]; then
    ops_section "ops monitor setup"
    ops_info "Preview only. Use --apply to write ${MONITOR_CONFIG#${OPS_PROJECT_ROOT}/}."
    if [[ "${ADD_POSTGRES}" == "true" || "${ADD_REDIS}" == "true" ]]; then
      ops_info "Would create ${INFRA_ENV_REL} for local infra credentials if missing."
    fi
  fi

  if [[ "${JSON}" == "true" || "${APPLY}" != "true" ]]; then
    jq '.' <<< "${config_json}"
  fi
}

_check_http() {
  local url="$1"
  command -v curl >/dev/null 2>&1 || { printf 'unknown	curl missing'; return 0; }
  if curl -fsS --max-time "${TIMEOUT_SECONDS}" "${url}" >/dev/null 2>&1; then
    printf 'up	http ok'
  else
    printf 'down	http failed'
  fi
}

_check_tcp() {
  local host="$1" port="$2"
  command -v timeout >/dev/null 2>&1 || { printf 'unknown	timeout missing'; return 0; }
  if timeout "${TIMEOUT_SECONDS}" bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1; then
    printf 'up	tcp open'
  else
    printf 'down	tcp closed'
  fi
}

_candidate_hosts_json() {
  require_bins jq
  local candidates='[]' host

  _candidate_add() {
    local label="$1" value="$2"
    [[ -n "${value}" ]] || return 0
    candidates="$(jq -c --arg label "${label}" --arg host "${value}" '
      if any(.[]; .host == $host) then . else . + [{label: $label, host: $host}] end
    ' <<< "${candidates}")"
  }

  _candidate_add "loopback" "127.0.0.1"

  host="$(ip route show default 2>/dev/null | sed -n 's/^default via \([^ ]*\).*/\1/p' | head -n1 || true)"
  _candidate_add "default_gateway" "${host}"

  host="$(grep -m1 '^nameserver ' /etc/resolv.conf 2>/dev/null | awk '{print $2}' || true)"
  _candidate_add "resolv_nameserver" "${host}"

  host="$(getent hosts host.docker.internal 2>/dev/null | awk 'NR == 1 {print $1}' || true)"
  _candidate_add "host.docker.internal" "${host}"

  printf '%s' "${candidates}"
}

_run_hosts() {
  require_bins jq
  [[ "${PROBE_PORT}" =~ ^[0-9]+$ ]] || die "ops monitor hosts requires --port=PORT" 2

  local candidates results='[]' item label host result state detail
  candidates="$(_candidate_hosts_json)"
  while IFS= read -r item; do
    [[ -n "${item}" ]] || continue
    label="$(jq -r '.label' <<< "${item}")"
    host="$(jq -r '.host' <<< "${item}")"
    result="$(_check_tcp "${host}" "${PROBE_PORT}")"
    state="${result%%$'\t'*}"
    detail="${result#*$'\t'}"
    results="$(jq -c \
      --arg label "${label}" \
      --arg host "${host}" \
      --arg port "${PROBE_PORT}" \
      --arg state "${state}" \
      --arg detail "${detail}" \
      '. + [{label: $label, host: $host, port: ($port | tonumber), state: $state, detail: $detail}]' \
      <<< "${results}")"
  done < <(jq -c '.[]' <<< "${candidates}")

  if [[ "${JSON}" == "true" ]]; then
    jq -n --argjson candidates "${results}" '{candidates: $candidates}'
    return 0
  fi

  ops_section "ops monitor hosts"
  printf '  %-22s %-18s %-8s %s\n' "LABEL" "HOST" "STATE" "DETAIL"
  jq -r '.[] | [.label, .host, .state, .detail] | @tsv' <<< "${results}" |
    while IFS=$'\t' read -r label host state detail; do
      printf '  %-22s %-18s %-8s %s\n' "${label}" "${host}" "${state}" "${detail}"
    done
}

_env_ref_value() {
  local env_name="$1"
  [[ -n "${env_name}" && "${env_name}" != "null" ]] || return 0
  printf '%s' "$(printenv "${env_name}" 2>/dev/null || true)"
}

_check_postgres() {
  local host="$1" port="$2" dbname="$3" user="$4" password="$5"
  command -v pg_isready >/dev/null 2>&1 || { printf 'unknown	pg_isready missing'; return 0; }
  local args=("-h" "${host}" "-p" "${port}" "-t" "${TIMEOUT_SECONDS}")
  [[ -n "${dbname}" ]] && args+=("-d" "${dbname}")
  [[ -n "${user}" ]] && args+=("-U" "${user}")
  if PGPASSWORD="${password}" pg_isready "${args[@]}" >/dev/null 2>&1; then
    printf 'up	postgres ready'
  else
    printf 'down	postgres not ready'
  fi
}

_postgres_target_json() {
  require_bins jq
  local targets target
  targets="$(_targets_json)"
  target="$(jq -c '[.[] | select(.kind == "postgres")][0] // empty' <<< "${targets}")"
  [[ -n "${target}" ]] || die "No postgres monitor target found. Run: ops monitor setup --postgres --apply" 2
  printf '%s' "${target}"
}

_postgres_info_json() {
  require_bins jq
  _load_infra_env
  local target id host port db_env user_env password_env db_value user_value password_value
  local pg_isready_status psql_status ready state detail
  target="$(_postgres_target_json)"
  id="$(jq -r '.id // "postgres.local"' <<< "${target}")"
  host="$(jq -r '.host // "127.0.0.1"' <<< "${target}")"
  port="$(jq -r '.port // 5432' <<< "${target}")"
  db_env="$(jq -r '.db_env // ""' <<< "${target}")"
  user_env="$(jq -r '.user_env // ""' <<< "${target}")"
  password_env="$(jq -r '.password_env // ""' <<< "${target}")"
  db_value="$(_env_ref_value "${db_env}")"
  user_value="$(_env_ref_value "${user_env}")"
  password_value="$(_env_ref_value "${password_env}")"
  pg_isready_status="$(_tool_status pg_isready)"
  psql_status="$(_tool_status psql)"
  ready="$(_check_postgres "${host}" "${port}" "${db_value}" "${user_value}" "${password_value}")"
  state="${ready%%$'\t'*}"
  detail="${ready#*$'\t'}"

  jq -n \
    --arg id "${id}" \
    --arg host "${host}" \
    --arg port "${port}" \
    --arg db_env "${db_env}" \
    --arg user_env "${user_env}" \
    --arg password_env "${password_env}" \
    --arg db "${db_value}" \
    --arg user "${user_value}" \
    --argjson db_present "$(if [[ -n "${db_value}" ]]; then printf true; else printf false; fi)" \
    --argjson user_present "$(if [[ -n "${user_value}" ]]; then printf true; else printf false; fi)" \
    --argjson password_present "$(if [[ -n "${password_value}" ]]; then printf true; else printf false; fi)" \
    --arg pg_isready_status "${pg_isready_status%%:*}" \
    --arg pg_isready_path "${pg_isready_status#*:}" \
    --arg psql_status "${psql_status%%:*}" \
    --arg psql_path "${psql_status#*:}" \
    --arg ready_state "${state}" \
    --arg ready_detail "${detail}" \
    '{
      target: {
        id: $id,
        kind: "postgres",
        host: $host,
        port: ($port | tonumber? // 5432)
      },
      env_file: ".ops.project/secrets/infra.env",
      connection: {
        db_env: $db_env,
        db: $db,
        db_present: $db_present,
        user_env: $user_env,
        user: $user,
        user_present: $user_present,
        password_env: $password_env,
        password_present: $password_present
      },
      tools: {
        pg_isready: {status: $pg_isready_status, path: $pg_isready_path},
        psql: {status: $psql_status, path: $psql_path}
      },
      readiness: {
        state: $ready_state,
        detail: $ready_detail
      }
    }'
}

_postgres_psql_json() {
  local sql="$1"
  command -v psql >/dev/null 2>&1 || die "psql is required for this command. Install postgresql-client or use ops monitor postgres info." 2
  _load_infra_env
  local target host port db_env user_env password_env db_value user_value password_value output
  target="$(_postgres_target_json)"
  host="$(jq -r '.host // "127.0.0.1"' <<< "${target}")"
  port="$(jq -r '.port // 5432' <<< "${target}")"
  db_env="$(jq -r '.db_env // ""' <<< "${target}")"
  user_env="$(jq -r '.user_env // ""' <<< "${target}")"
  password_env="$(jq -r '.password_env // ""' <<< "${target}")"
  db_value="$(_env_ref_value "${db_env}")"
  user_value="$(_env_ref_value "${user_env}")"
  password_value="$(_env_ref_value "${password_env}")"
  [[ -n "${db_value}" ]] || db_value="postgres"

  local args=("-h" "${host}" "-p" "${port}" "-d" "${db_value}" "-X" "-q" "-t" "-A" "-v" "ON_ERROR_STOP=1" "-c" "${sql}")
  [[ -n "${user_value}" ]] && args+=("-U" "${user_value}")
  output="$(PGPASSWORD="${password_value}" psql "${args[@]}" 2>/dev/null | sed -n 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/!p' | tail -n1 || true)"
  [[ -n "${output}" ]] || die "Postgres query failed. Check ops monitor postgres info and credentials." 1
  jq -c '.' <<< "${output}" >/dev/null
  printf '%s' "${output}"
}

_run_postgres_info() {
  local report state detail
  report="$(_postgres_info_json)"
  if [[ "${JSON}" == "true" ]]; then
    jq '.' <<< "${report}"
    return 0
  fi

  ops_section "ops monitor postgres info"
  state="$(jq -r '.readiness.state' <<< "${report}")"
  detail="$(jq -r '.readiness.detail' <<< "${report}")"
  printf '  %-18s %s\n' "target" "$(jq -r '.target.id' <<< "${report}")"
  printf '  %-18s %s:%s\n' "address" "$(jq -r '.target.host' <<< "${report}")" "$(jq -r '.target.port' <<< "${report}")"
  printf '  %-18s %s\n' "database" "$(jq -r '.connection.db' <<< "${report}")"
  printf '  %-18s %s\n' "user" "$(jq -r '.connection.user' <<< "${report}")"
  printf '  %-18s %s\n' "password" "$(jq -r 'if .connection.password_present then "set" else "empty" end' <<< "${report}")"
  printf '  %-18s %s (%s)\n' "pg_isready" "$(jq -r '.tools.pg_isready.status' <<< "${report}")" "$(jq -r '.tools.pg_isready.path' <<< "${report}")"
  printf '  %-18s %s (%s)\n' "psql" "$(jq -r '.tools.psql.status' <<< "${report}")" "$(jq -r '.tools.psql.path' <<< "${report}")"
  printf '  %-18s %s - %s\n' "readiness" "${state}" "${detail}"
}

_run_postgres_databases() {
  local rows
  rows="$(_postgres_psql_json "select coalesce(json_agg(json_build_object('name', datname, 'owner', pg_get_userbyid(datdba), 'encoding', pg_encoding_to_char(encoding), 'allow_connections', datallowconn) order by datname), '[]'::json) from pg_database;")"
  if [[ "${JSON}" == "true" ]]; then
    jq -n --argjson databases "${rows}" '{databases: $databases}'
    return 0
  fi
  ops_section "ops monitor postgres databases"
  printf '  %-28s %-18s %-10s %s\n' "DATABASE" "OWNER" "ENCODING" "ALLOW_CONNECTIONS"
  jq -r '.[] | [.name, .owner, .encoding, (.allow_connections | tostring)] | @tsv' <<< "${rows}" |
    while IFS=$'\t' read -r name owner encoding allow_connections; do
      printf '  %-28s %-18s %-10s %s\n' "${name}" "${owner}" "${encoding}" "${allow_connections}"
    done
}

_run_postgres_users() {
  local rows
  rows="$(_postgres_psql_json "select coalesce(json_agg(json_build_object('name', rolname, 'can_login', rolcanlogin, 'superuser', rolsuper, 'create_db', rolcreatedb, 'create_role', rolcreaterole) order by rolname), '[]'::json) from pg_roles;")"
  if [[ "${JSON}" == "true" ]]; then
    jq -n --argjson users "${rows}" '{users: $users}'
    return 0
  fi
  ops_section "ops monitor postgres users"
  printf '  %-28s %-10s %-10s %-10s %s\n' "ROLE" "LOGIN" "SUPERUSER" "CREATE_DB" "CREATE_ROLE"
  jq -r '.[] | [.name, (.can_login | tostring), (.superuser | tostring), (.create_db | tostring), (.create_role | tostring)] | @tsv' <<< "${rows}" |
    while IFS=$'\t' read -r name can_login superuser create_db create_role; do
      printf '  %-28s %-10s %-10s %-10s %s\n' "${name}" "${can_login}" "${superuser}" "${create_db}" "${create_role}"
    done
}

_run_postgres() {
  case "${POSTGRES_ACTION}" in
    help|--help|-h) _usage_monitor ;;
    info|"") _run_postgres_info ;;
    databases) _run_postgres_databases ;;
    users) _run_postgres_users ;;
  esac
}

_check_redis() {
  local host="$1" port="$2" db="$3" password="$4"
  command -v redis-cli >/dev/null 2>&1 || { printf 'unknown	redis-cli missing'; return 0; }
  local args=("-h" "${host}" "-p" "${port}" "--raw")
  [[ -n "${db}" && "${db}" =~ ^[0-9]+$ ]] && args+=("-n" "${db}")
  local reply
  if [[ -n "${password}" ]]; then
    reply="$(REDISCLI_AUTH="${password}" redis-cli "${args[@]}" ping 2>/dev/null | sed -n '1p')"
  else
    reply="$(redis-cli "${args[@]}" ping 2>/dev/null | sed -n '1p')"
  fi
  if [[ "${reply}" == "PONG" ]]; then
    printf 'up	redis pong'
  else
    printf 'down	redis ping failed'
  fi
}

_target_result_json() {
  local target="$1"
  local id kind host port url service source result state detail
  local db_env user_env password_env db_value user_value password_value
  id="$(jq -r '.id // ""' <<< "${target}")"
  kind="$(jq -r '.kind // "tcp"' <<< "${target}")"
  host="$(jq -r '.host // "127.0.0.1"' <<< "${target}")"
  port="$(jq -r '.port // 0' <<< "${target}")"
  url="$(jq -r '.url // ""' <<< "${target}")"
  service="$(jq -r '.service // ""' <<< "${target}")"
  source="$(jq -r '.source // "monitoring.config"' <<< "${target}")"
  db_env="$(jq -r '.db_env // ""' <<< "${target}")"
  user_env="$(jq -r '.user_env // ""' <<< "${target}")"
  password_env="$(jq -r '.password_env // ""' <<< "${target}")"
  db_value="$(_env_ref_value "${db_env}")"
  user_value="$(_env_ref_value "${user_env}")"
  password_value="$(_env_ref_value "${password_env}")"
  [[ -n "${id}" ]] || id="${kind}:${host}:${port}${url}"

  case "${kind}" in
    http) result="$(_check_http "${url}")" ;;
    tcp) result="$(_check_tcp "${host}" "${port}")" ;;
    postgres) result="$(_check_postgres "${host}" "${port}" "${db_value}" "${user_value}" "${password_value}")" ;;
    redis) result="$(_check_redis "${host}" "${port}" "${db_value}" "${password_value}")" ;;
    *) result="unknown	unsupported kind: ${kind}" ;;
  esac
  state="${result%%$'\t'*}"
  detail="${result#*$'\t'}"

  jq -n \
    --arg id "${id}" \
    --arg kind "${kind}" \
    --arg service "${service}" \
    --arg source "${source}" \
    --arg host "${host}" \
    --arg port "${port}" \
    --arg url "${url}" \
    --arg state "${state}" \
    --arg detail "${detail}" \
    '{
      id: $id,
      kind: $kind,
      service: $service,
      source: $source,
      host: $host,
      port: ($port | tonumber? // 0),
      url: $url,
      state: $state,
      detail: $detail
    }'
}

_run_status() {
  require_bins jq
  _load_infra_env
  local targets results='[]' target result_json down_count unknown_count
  targets="$(_targets_json)"
  if [[ -n "${TARGET}" ]]; then
    targets="$(jq -c --arg id "${TARGET}" '[.[] | select(.id == $id)]' <<< "${targets}")"
  fi

  while IFS= read -r target; do
    [[ -n "${target}" ]] || continue
    result_json="$(_target_result_json "${target}")"
    results="$(jq -c --argjson item "${result_json}" '. + [$item]' <<< "${results}")"
  done < <(jq -c '.[]' <<< "${targets}")

  down_count="$(jq '[.[] | select(.state == "down")] | length' <<< "${results}")"
  unknown_count="$(jq '[.[] | select(.state == "unknown")] | length' <<< "${results}")"

  if [[ "${JSON}" == "true" ]]; then
    jq -n \
      --arg generated_at "$(ops_timestamp)" \
      --arg mode "${SUBCMD}" \
      --argjson strict "${STRICT}" \
      --argjson down "${down_count}" \
      --argjson unknown "${unknown_count}" \
      --argjson targets "${results}" \
      '{
        version: 1,
        generated_at: $generated_at,
        mode: $mode,
        strict: $strict,
        summary: {
          total: ($targets | length),
          down: $down,
          unknown: $unknown,
          ok: ($down == 0 and ((if $strict then $unknown else 0 end) == 0))
        },
        targets: $targets
      }'
    if [[ "${SUBCMD}" == "test" ]]; then
      if [[ "${down_count}" != "0" || ( "${STRICT}" == "true" && "${unknown_count}" != "0" ) ]]; then
        return 1
      fi
    fi
    return 0
  fi

  if [[ "${SUBCMD}" == "test" ]]; then
    ops_section "ops monitor test"
  else
    ops_section "ops monitor status"
  fi
  if [[ "$(jq 'length' <<< "${results}")" == "0" ]]; then
    ops_info "No monitor targets found. Add service ports/healthchecks or .ops.project/config/monitoring.json."
    return 0
  fi
  printf '  %-24s %-10s %-8s %s\n' "TARGET" "KIND" "STATE" "DETAIL"
  jq -r '.[] | [.id, .kind, .state, .detail] | @tsv' <<< "${results}" |
    while IFS=$'\t' read -r id kind state detail; do
      printf '  %-24s %-10s %-8s %s\n' "${id}" "${kind}" "${state}" "${detail}"
    done

  if [[ "${SUBCMD}" == "test" ]]; then
    if [[ "${down_count}" != "0" ]]; then
      ops_error "${down_count} monitor target(s) down."
      return 1
    fi
    if [[ "${STRICT}" == "true" && "${unknown_count}" != "0" ]]; then
      ops_error "${unknown_count} monitor target(s) unknown."
      return 1
    fi
    ops_ok "Monitor test passed."
  fi
}

case "${SUBCMD}" in
  doctor) _run_doctor ;;
  credentials|env) _run_credentials ;;
  hosts) _run_hosts ;;
  postgres) _run_postgres ;;
  setup) _run_setup ;;
  status|test) _run_status ;;
esac
