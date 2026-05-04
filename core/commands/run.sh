#!/usr/bin/env bash
# .ops-core/commands/run.sh — Execution dispatcher for Phase 3+.
#
# Usage: ops experimental run <action> <service_id>
#
# Exit codes:
#   2: Config error (unknown service, unknown action)
#   3: Preflight error (missing binary, bad path)
#   4: Dependency error (Phase 4)
#   5: Command failure

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/settings.sh"
source "${_SELF_DIR}/../lib/setup.sh"
source "${_SELF_DIR}/../lib/env.sh"
source "${_SELF_DIR}/../lib/env_materialize.sh"
source "${_SELF_DIR}/../lib/preflight.sh"

# ── Parse arguments ──────────────────────────────────────────────────────────
MODE=""
ACTION=""
SVC_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --mode=*) MODE="${1#*=}"; shift ;;
    --foreground) MODE="foreground"; shift ;;
    --background) MODE="background"; shift ;;
    help|--help|-h)
      printf 'Usage: ops run <action> <service_id> [--mode foreground|background]\n'
      exit 0
      ;;
    -*) ops_error "Unknown flag: $1"; exit 2 ;;
    *)
      if [[ -z "$ACTION" ]]; then ACTION="$1"
      elif [[ -z "$SVC_ID" ]]; then SVC_ID="$1"
      else ops_error "Usage: ops experimental run <action> <service_id> [--mode foreground|background]"; exit 2; fi
      shift
      ;;
  esac
done

if [[ -z "$ACTION" || -z "$SVC_ID" ]]; then
  ops_error "Usage: ops run <action> <service_id> [--mode foreground|background]"
  exit 2
fi

if [[ -z "${MODE}" ]]; then
  MODE="$(ops_setting_mode '.run.default_mode' 'foreground')"
fi
case "${MODE}" in
  foreground|background) ;;
  *) die "Invalid --mode '${MODE}' (expected foreground or background)" 2 ;;
esac

# ── Validate Config ──────────────────────────────────────────────────────────
require_manifest

if ! manifest_list_services | grep -qFx "${SVC_ID}"; then
  ops_error "Unknown service: '${SVC_ID}'"
  exit 2
fi

SVC_PATH="$(manifest_get_service_field "${SVC_ID}" path)"
if [[ -z "${SVC_PATH}" || "${SVC_PATH}" == "null" ]]; then
  ops_error "Service '${SVC_ID}' has no 'path' defined."
  exit 2
fi
ABS_PATH="${OPS_PROJECT_ROOT}/${SVC_PATH}"

export OPS_SERVICE_ID="${SVC_ID}"
export OPS_ACTION="${ACTION}"
if [[ ! -d "${ABS_PATH}" ]]; then
  ops_error "Service directory not found: ${ABS_PATH}"
  exit 3
fi

STACK="$(manifest_get_service_field "${SVC_ID}" stack)"
if [[ -z "${STACK}" || "${STACK}" == "null" ]]; then
  ops_error "Service '${SVC_ID}' has no 'stack' defined."
  exit 2
fi
RUNNER_KIND="$(manifest_get_service_field "${SVC_ID}" "runner.kind")"

AUTO_CONDA_ENV=""
if [[ "${ACTION}" == "start" && "${STACK}" == "django" && -z "${OPS_CONDA_ENV:-}" ]]; then
  AUTO_CONDA_ENV="$(setup_service_django_conda_env "${SVC_ID}")"
fi

export OPS_STACK="${STACK}"
export OPS_SVC_PATH="${ABS_PATH}"
export OPS_RUN_MODE="${MODE}"

# We allow any arbitrary action, but we can look up the explicit string in manifest
EXPLICIT_CMD="$(manifest_get_service_field "${SVC_ID}" "actions.${ACTION}")"
SETUP_CMD=""
if [[ "${ACTION}" == "start" ]]; then
  SETUP_CMD="$(setup_service_start_command "${SVC_ID}")"
fi

# ── Preflight Checks ─────────────────────────────────────────────────────────
preflight_check_stack "${STACK}"

# ── Setup Environment ────────────────────────────────────────────────────────
# Materialize env files (e.g. symlink) if requested by manifest
env_materialize_dispatch "${SVC_ID}"

# We must ensure env materialization is cleaned up
_cleanup() {
  env_materialize_cleanup "${SVC_ID}"
}
trap '_cleanup' EXIT INT TERM

# Export OPS_LOG_SERVICE for log multiplexing
export OPS_LOG_SERVICE="${SVC_ID}"

# ── Resolve Strategy & Execute ───────────────────────────────────────────────
# Command resolution:
# 1. Setup command from .ops.project / .ops.yaml (for start)
# 2. Local override: .ops/commands/<service>/<action>.sh
# 3. Stack strategy: .ops-core/stacks/<stack>.sh
# 4. Explicit command: .ops.yaml action string

_ensure_runtime_file() {
  local file="$1"
  local label="$2"

  if : >> "${file}" 2>/dev/null; then
    return 0
  fi

  # WSL on Windows-mounted drives can occasionally see a newly-created
  # directory before file creation works through drvfs. Ask Windows to create
  # the file, then retry the normal shell write.
  if command -v powershell.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    local win_file
    win_file="$(wslpath -w "${file}" 2>/dev/null | tr -d '\r' || true)"
    if [[ -n "${win_file}" ]]; then
      local wsl_env="WIN_TARGET"
      [[ -n "${WSLENV:-}" ]] && wsl_env="WIN_TARGET:${WSLENV}"
      WSLENV="${wsl_env}" WIN_TARGET="${win_file}" powershell.exe -NoProfile -NonInteractive -Command \
        '$path = $env:WIN_TARGET; $dir = Split-Path -Parent $path; New-Item -ItemType Directory -Force -Path $dir | Out-Null; if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType File -Path $path -Force | Out-Null }' \
        >/dev/null 2>&1 || true
      if : >> "${file}" 2>/dev/null; then
        return 0
      fi
    fi
  fi

  ops_error "Cannot write ${label} file: ${file}"
  return 5
}

_line_count() {
  local file="$1"
  awk 'END { print NR + 0 }' "${file}" 2>/dev/null || printf '0'
}

_preview_background_log() {
  local log_file="$1"
  local start_line="$2"
  local preview_enabled preview_lines preview_wait preview_output

  preview_enabled="$(ops_setting_bool '.start.preview.enabled' 'true')"
  [[ "${preview_enabled}" == "true" ]] || return 0

  preview_lines="$(ops_setting_int '.start.preview.lines' '20')"
  preview_wait="$(ops_setting_int '.start.preview.wait_seconds' '1')"
  (( preview_lines > 0 )) || return 0

  if (( preview_wait > 0 )); then
    sleep "${preview_wait}"
  fi

  preview_output="$(awk -v start="${start_line}" -v max="${preview_lines}" '
    NR > start && count < max { print; count++ }
    END { if (count == 0) exit 1 }
  ' "${log_file}" 2>/dev/null)" || {
    ops_info "No startup log output yet. Follow with: ./ops.sh logs ${SVC_ID} --follow"
    return 0
  }

  ops_info "Startup log preview from .ops.project/logs/${SVC_ID}.log:"
  printf '%s\n' "${preview_output}" | _ops_log_stream
}

_is_python_env_failure_log() {
  local log_file="$1"
  [[ -f "${log_file}" ]] || return 1

  grep -Eiq "ModuleNotFoundError:[[:space:]]+No module named|ImportError:[[:space:]]+Couldn't import Django|python:[[:space:]]+command not found" "${log_file}"
}

_is_port_in_use_log() {
  local log_file="$1"
  [[ -f "${log_file}" ]] || return 1

  grep -Eiq "Error:[[:space:]]+That port is already in use\.|\[Errno 98\][[:space:]]+Address already in use" "${log_file}"
}

_run_isolated() {
  local cmd="$1"

  _env_exec_run() {
    if [[ -n "${AUTO_CONDA_ENV:-}" && -z "${OPS_CONDA_ENV:-}" ]]; then
      OPS_CONDA_ENV="${AUTO_CONDA_ENV}" env_exec "${SVC_ID}" -- "$@"
    else
      env_exec "${SVC_ID}" -- "$@"
    fi
  }

  if [[ "${MODE}" == "background" ]]; then
    local log_dir="${OPS_PROJECT_LOG_DIR}"
    local run_dir="${OPS_PROJECT_RUN_DIR}"
    local log_file="${OPS_PROJECT_LOG_DIR}/${SVC_ID}.log"
    local pid_file="${OPS_PROJECT_RUN_DIR}/${SVC_ID}.pid"

    if ! mkdir -p "${log_dir}" "${run_dir}"; then
      ops_error "Failed to create runtime directories: ${log_dir}, ${run_dir}"
      return 5
    fi
    if [[ ! -d "${log_dir}" || ! -d "${run_dir}" ]]; then
      ops_error "Runtime paths must be directories: ${log_dir}, ${run_dir}"
      return 5
    fi
    if ! _ensure_runtime_file "${log_file}" "log"; then
      return 5
    fi
    if ! _ensure_runtime_file "${pid_file}" "pid"; then
      return 5
    fi
    if ! : > "${pid_file}"; then
      ops_error "Cannot write pid file: ${pid_file}"
      return 5
    fi
    local start_line
    start_line="$(_line_count "${log_file}")"
    
    # Use stdbuf to force line-buffered output if available (helps streamed logs)
    local _stdbuf_cmd=""
    if command -v stdbuf >/dev/null 2>&1; then
      _stdbuf_cmd="stdbuf -oL -eL"
    fi

    # Run in background and save PID
    _env_exec_run ${_stdbuf_cmd} bash -c "${cmd}" >> "${log_file}" 2>&1 < /dev/null &
    local bg_pid=$!
    disown "${bg_pid}" 2>/dev/null || true
    echo "${bg_pid}" > "${pid_file}"
    ops_ok "Started in background (PID ${bg_pid}). Logs: .ops.project/logs/${SVC_ID}.log"
    _preview_background_log "${log_file}" "${start_line}"
    return 0
  else
    local code=0
    local retry_log=""

    retry_log="$(mktemp "${TMPDIR:-/tmp}/ops-run-${SVC_ID}-XXXXXX.log")"

    if type _ops_log_stream >/dev/null 2>&1; then
      set +e
      local _stdbuf_cmd=""
      if command -v stdbuf >/dev/null 2>&1; then
        _stdbuf_cmd="stdbuf -oL -eL"
      fi
      _env_exec_run ${_stdbuf_cmd} bash -c "${cmd}" > >(tee "${retry_log}" | _ops_log_stream) 2>&1
      code=$?
      set -e
    else
      set +e
      local _stdbuf_cmd=""
      if command -v stdbuf >/dev/null 2>&1; then
        _stdbuf_cmd="stdbuf -oL -eL"
      fi
      _env_exec_run ${_stdbuf_cmd} bash -c "${cmd}" > >(tee "${retry_log}") 2>&1
      code=$?
      set -e
    fi

    if [[ ${code} -ne 0 && "${ACTION}" == "start" && ( "${STACK}" == "django" || "${STACK}" == "custom" ) ]] && _is_python_env_failure_log "${retry_log}"; then
      rm -f "${retry_log}" >/dev/null 2>&1 || true
      return 6
    fi

    if [[ ${code} -ne 0 && "${ACTION}" == "start" ]] && _is_port_in_use_log "${retry_log}"; then
      rm -f "${retry_log}" >/dev/null 2>&1 || true
      return 7
    fi

    rm -f "${retry_log}" >/dev/null 2>&1 || true
    return ${code}
  fi
}

SVC_OVERRIDE="${OPS_PROJECT_ROOT}/.ops/commands/${SVC_ID}/${ACTION}.sh"
GLOBAL_OVERRIDE="${OPS_PROJECT_ROOT}/.ops/commands/${ACTION}.sh"
STACK_FILE="${_SELF_DIR}/../stacks/${STACK}.sh"

# Resolution order for action execution:
# 1. Local override: .ops/commands/<service>/<action>.sh (highest priority — user customization)
# 2. Global override: .ops/commands/<action>.sh (applies to all services)
# 3. Setup command: generated setup.json (auto-generated, lower priority)
# 4. Stack strategy: .ops/core/stacks/<stack>.sh (fallback)
# 5. Explicit command: .ops.yaml manifest (least priority)

if [[ "${RUNNER_KIND}" != "process_group" && -f "${SVC_OVERRIDE}" && -x "${SVC_OVERRIDE}" ]]; then
  ops_info "Running local override: .ops/commands/${SVC_ID}/${ACTION}.sh"
  _run_isolated "cd '${ABS_PATH}' && '${SVC_OVERRIDE}'"
  EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 ]]; then exit $EXIT_CODE; else exit 0; fi
elif [[ "${RUNNER_KIND}" != "process_group" && -f "${GLOBAL_OVERRIDE}" && -x "${GLOBAL_OVERRIDE}" ]]; then
  ops_info "Running global override: .ops/commands/${ACTION}.sh"
  _run_isolated "cd '${ABS_PATH}' && '${GLOBAL_OVERRIDE}'"
  EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 ]]; then exit $EXIT_CODE; else exit 0; fi
elif [[ "${RUNNER_KIND}" != "process_group" && "${ACTION}" == "start" && -n "${SETUP_CMD}" && "${SETUP_CMD}" != "null" ]]; then
  ops_info "Running setup command: .ops.project generated setup for ${SVC_ID}"
  _run_isolated "cd '${ABS_PATH}' && ${SETUP_CMD}"
  EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 ]]; then exit $EXIT_CODE; else exit 0; fi
fi

# Need to run the stack/explicit logic inside env_exec. We can write a wrapper script
# string that handles the resolution, or export functions. Exporting functions is messy.
# We will construct a bash command string to execute via `env_exec`.

# We will source the stack file inside the subshell, then run the dispatch function.
# If dispatch returns 10, we fallback to eval EXPLICIT_CMD if not empty.

if [[ ! -f "${STACK_FILE}" ]]; then
  ops_error "Stack strategy not found: ${STACK_FILE}"
  exit 2
fi

STACK_DISPATCH_FUNC="${STACK//-/_}_dispatch"

# Construct the subshell logic
SUBSHELL_CMD=$(cat <<EOF
  cd '${ABS_PATH}' || exit 3
  source '${STACK_FILE}'
  
  if type '${STACK_DISPATCH_FUNC}' >/dev/null 2>&1; then
    '${STACK_DISPATCH_FUNC}' '${ACTION}' '${EXPLICIT_CMD}'
    CODE=\$?
    if [[ \$CODE -eq 10 ]]; then
      # Not implemented by stack, check explicit command again (fallback)
      if [[ -n '${EXPLICIT_CMD}' && '${EXPLICIT_CMD}' != 'null' ]]; then
        eval '${EXPLICIT_CMD}'
        CODE=\$?
      else
        # --- PHASE 8: COMPATIBILITY BRIDGE ---
        LEGACY_REGISTRY="${OPS_PROJECT_ROOT}/scripts/commands.sh"
        if [[ -f "\${LEGACY_REGISTRY}" ]]; then
          # Extract mapped script path from the legacy registry
          TARGET_SCRIPT="\$(bash -c "source '\${LEGACY_REGISTRY}' >/dev/null 2>&1 && echo \"\\\${COMMAND_SCRIPTS[${ACTION}]}\"")"
          if [[ -n "\${TARGET_SCRIPT}" ]]; then
            echo "[INFO] Bridging to legacy script: scripts/\${TARGET_SCRIPT}" >&2
            
            # Argument translation
            BRIDGE_ARGS=()
            case "${ACTION}" in
              build|deploy|staging|release|update|publish|hotswap)
                BRIDGE_ARGS+=("--services" "${SVC_ID}")
                ;;
              *)
                BRIDGE_ARGS+=("${SVC_ID}")
                ;;
            esac
            
            # Run legacy script from project root
            cd "${OPS_PROJECT_ROOT}" || exit 3
            bash "${OPS_PROJECT_ROOT}/scripts/\${TARGET_SCRIPT}" "\${BRIDGE_ARGS[@]}"
            CODE=\$?
            exit \$CODE
          fi
        fi

        echo "[ERROR] Action '${ACTION}' is neither implemented by stack '${STACK}', explicitly defined in manifest, nor bridged in scripts/commands.sh" >&2
        exit 2
      fi
    fi
    exit \$CODE
  else
    echo "[ERROR] Stack file '${STACK_FILE}' missing dispatch function '${STACK_DISPATCH_FUNC}'" >&2
    exit 2
  fi
EOF
)

# Run isolated
_run_isolated "${SUBSHELL_CMD}"
EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]]; then
  # If the subshell exited with 2 or 3, bubble it up directly (config/preflight)
  if [[ ${EXIT_CODE} -eq 2 || ${EXIT_CODE} -eq 3 || ${EXIT_CODE} -eq 6 || ${EXIT_CODE} -eq 7 ]]; then
    exit "${EXIT_CODE}"
  fi
  # Otherwise it's a command failure
  exit 5
fi

exit 0
