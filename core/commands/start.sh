#!/usr/bin/env bash
# .ops-core/commands/start.sh — Dependency-aware recursive start.
#
# Usage: ops experimental start [<service_id> | --all] [--with-deps | --no-deps]
#
# Flags:
#   --with-deps  Start dependencies before the requested service(s) (Default)
#   --no-deps    Only start the requested service(s)
#   --foreground Run services in the foreground (overrides .ops.yaml settings)
#   --background Run services in the background (overrides .ops.yaml settings)
#   --dry-run    Print execution order without starting services

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/manifest.sh"
source "${_SELF_DIR}/../lib/settings.sh"
source "${_SELF_DIR}/../lib/setup.sh"
source "${_SELF_DIR}/../lib/graph.sh"

START_INTERRUPTED=false

_mark_interrupted() {
  START_INTERRUPTED=true
}

trap '_mark_interrupted' INT TERM

_can_prompt_user() {
  [[ -e /dev/tty && "${OPS_NON_INTERACTIVE:-false}" != "true" ]]
}

_prompt_conda_env() {
  local tty_in="/dev/tty"
  local answer=""
  local env_name=""

  if ! _can_prompt_user; then
    return 1
  fi

  ops_warn "The service failed because Python/Django is not available in the current environment."
  printf 'Activate a Conda environment and retry? [y/N]: ' > "${tty_in}"
  read -r answer < "${tty_in}" || return 1
  case "${answer}" in
    y|Y|yes|YES)
      ;;
    *)
      return 1
      ;;
  esac

  if command -v conda >/dev/null 2>&1; then
    printf '\nAvailable Conda environments:\n' > "${tty_in}"
    conda env list 2>/dev/null | sed 's/^/  /' > "${tty_in}" || true
  fi

  printf 'Enter Conda environment name to activate: ' > "${tty_in}"
  read -r env_name < "${tty_in}" || return 1
  [[ -n "${env_name}" ]] || return 1

  printf '%s' "${env_name}"
  return 0
}

_resolve_conda_base() {
  if command -v conda >/dev/null 2>&1; then
    conda info --base 2>/dev/null || true
    return 0
  fi

  local candidate
  for candidate in "${HOME:-}/miniconda3" "${HOME:-}/anaconda3" "/home/dev/miniconda3" "/home/dev/anaconda3"; do
    if [[ -f "${candidate}/etc/profile.d/conda.sh" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done

  return 1
}

_persist_django_conda_env() {
  local service_id="$1"
  local env_name="$2"
  local current_manager=""
  local current_env=""
  [[ -n "${env_name}" ]] || return 0

  require_bins yq

  yq e -i ".setup.services.\"${service_id}\".django.conda_env = \"${env_name}\"" "${OPS_MANIFEST}"

  current_manager="$(yq e '.setup.runtimes.python.manager // ""' "${OPS_MANIFEST}" 2>/dev/null || true)"
  if [[ -z "${current_manager}" || "${current_manager}" == "null" ]]; then
    yq e -i '.setup.runtimes.python.manager = "conda"' "${OPS_MANIFEST}"
  fi

  current_env="$(yq e '.setup.runtimes.python.env // ""' "${OPS_MANIFEST}" 2>/dev/null || true)"
  if [[ -z "${current_env}" || "${current_env}" == "null" ]]; then
    yq e -i ".setup.runtimes.python.env = \"${env_name}\"" "${OPS_MANIFEST}"
  fi

  mkdir -p "${OPS_PROJECT_GENERATED_DIR}"
  yq e -o=json -I=2 '.setup' "${OPS_MANIFEST}" > "${OPS_PROJECT_SETUP_GENERATED_FILE}"
}

# ── Parse arguments ──────────────────────────────────────────────────────────
TARGET=""
WITH_DEPS="$(ops_setting_bool '.start.with_deps' 'true')"
START_MODE="$(ops_setting_mode '.start.mode' 'background')"
DRY_RUN=false

_usage_start() {
  printf 'Usage: ops start [<service_id> | --all] [--with-deps | --no-deps] [--foreground | --background] [--dry-run]\n'
}

for _arg in "$@"; do
  case "${_arg}" in
    help|--help|-h) _usage_start; exit 0 ;;
    --all)
      if [[ -z "${TARGET}" ]]; then
        TARGET="--all"
      else
        die "Multiple targets not supported. Use '<service_id>' or '--all'."
      fi
      ;;
    --with-deps) WITH_DEPS=true ;;
    --no-deps)   WITH_DEPS=false ;;
    --foreground) START_MODE="foreground" ;;
    --background) START_MODE="background" ;;
    --mode=*)    START_MODE="${_arg#*=}" ;;
    --dry-run)   DRY_RUN=true ;;
    -*)          die "Unknown flag: ${_arg}" ;;
    *)
      if [[ -z "${TARGET}" ]]; then
        TARGET="${_arg}"
      else
        die "Multiple targets not supported. Use '<service_id>' or '--all'."
      fi
      ;;
  esac
done

if [[ -z "${TARGET}" ]]; then
  _usage_start >&2
  exit 2
fi
case "${START_MODE}" in
  foreground|background) ;;
  *) die "Invalid start mode '${START_MODE}' (expected foreground or background)" 2 ;;
esac

require_manifest

# Early cycle check ensures we don't start executing a broken graph
graph_cycle_check

# ── Determine Execution List ─────────────────────────────────────────────────
EXEC_LIST=()

if [[ "${TARGET}" == "--all" ]]; then
  # For --all, topological sort covers everything
  read -ra EXEC_LIST <<< "$(graph_topo_sort "--all")"
else
  if ! printf ' %s ' "$(manifest_list_services | tr '\n' ' ')" | grep -qF " ${TARGET} "; then
    ops_error "Unknown service: '${TARGET}'"
    exit 2
  fi
  
  if [[ "${WITH_DEPS}" == "true" ]]; then
    read -ra EXEC_LIST <<< "$(graph_topo_sort "${TARGET}")"
  else
    EXEC_LIST=("${TARGET}")
  fi
fi

# ── Execute ──────────────────────────────────────────────────────────────────
ops_section "ops experimental start"

if [[ ${#EXEC_LIST[@]} -eq 0 ]]; then
  ops_ok "Nothing to start."
  exit 0
fi

ops_info "Execution order: ${EXEC_LIST[*]}"
ops_info "Start mode: ${START_MODE}"
printf '\n'

if [[ "${DRY_RUN}" == "true" ]]; then
  ops_ok "Dry-run complete. No services were started."
  exit 0
fi

for SVC in "${EXEC_LIST[@]+"${EXEC_LIST[@]}"}"; do
  # Status probe via run engine (we use bash -c to suppress stderr if stack prints warnings)
  STATUS_CODE=1
  # Execute run status quietly
  if bash "${_SELF_DIR}/run.sh" "status" "${SVC}" >/dev/null 2>&1; then
    STATUS_CODE=0
  else
    STATUS_CODE=$?
  fi

  if [[ ${STATUS_CODE} -eq 0 ]]; then
    # Already running
    ops_ok "[${SVC}] Already running (skipped)"
    if [[ "${START_MODE}" == "foreground" && ${#EXEC_LIST[@]} -eq 1 ]]; then
      ops_info "[${SVC}] Following logs (Ctrl+C to detach)."
      bash "${_SELF_DIR}/logs.sh" "${SVC}" --follow
    fi
  else
    # STATUS_CODE 1 (not running) or 10 (not implemented locally)
    ops_info "[${SVC}] Starting..."
    set +e
    bash "${_SELF_DIR}/run.sh" --mode "${START_MODE}" "start" "${SVC}"
    RUN_CODE=$?
    set -e
    if [[ "${START_INTERRUPTED}" == "true" || ${RUN_CODE} -eq 130 ]]; then
      ops_warn "Interrupted by user."
      exit 130
    fi
    if [[ ${RUN_CODE} -ne 0 ]]; then
      if [[ ${RUN_CODE} -eq 6 ]]; then
        CONDA_ENV="$(_prompt_conda_env || true)"
        if [[ -n "${CONDA_ENV}" ]]; then
          _persist_django_conda_env "${SVC}" "${CONDA_ENV}"
          CONDA_BASE="$(_resolve_conda_base || true)"
          ops_info "Retrying '[${SVC}]' with Conda env '${CONDA_ENV}'."
          set +e
          OPS_CONDA_ENV="${CONDA_ENV}" OPS_CONDA_BASE="${CONDA_BASE}" bash "${_SELF_DIR}/run.sh" --mode "${START_MODE}" "start" "${SVC}"
          RUN_CODE=$?
          set -e
          if [[ "${START_INTERRUPTED}" == "true" || ${RUN_CODE} -eq 130 ]]; then
            ops_warn "Interrupted by user."
            exit 130
          fi
          if [[ ${RUN_CODE} -ne 0 ]]; then
            if [[ ${RUN_CODE} -eq 7 ]]; then
              ops_error "Failed to start '${SVC}': application port is already in use."
              ops_info "A process is already listening on the configured port. Check with: ss -ltnp | grep :8000"
              ops_info "If this is the same service, stop it first or use 'ops run status ${SVC}' to inspect state."
              exit 5
            else
              ops_error "Failed to start '${SVC}' even after activating Conda env '${CONDA_ENV}'."
              exit 5
            fi
          fi
        else
          ops_error "Python/Django environment is missing for '${SVC}'."
          exit 5
        fi
      elif [[ ${RUN_CODE} -eq 7 ]]; then
        ops_error "Failed to start '${SVC}': application port is already in use."
        ops_info "A process is already listening on the configured port. Check with: ss -ltnp | grep :8000"
        ops_info "If this is the same service, stop it first or use 'ops run status ${SVC}' to inspect state."
        exit 5
      else
        ops_error "Failed to start '${SVC}'"
        exit 5
      fi
    fi
  fi
done

printf '\n'
ops_ok "Start sequence complete."
