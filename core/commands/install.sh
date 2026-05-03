#!/usr/bin/env bash
# .ops/core/commands/install.sh — Idempotent ops installation/repair.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"

DRY_RUN=false
REPAIR=false
SUBCMD="${1:-}"

if [[ "${SUBCMD}" == "doctor" ]]; then
  shift
fi

for _arg in "$@"; do
  case "${_arg}" in
    --dry-run) DRY_RUN=true ;;
    --repair) REPAIR=true ;;
    --help|-h)
      cat <<'EOF'
Usage: ops install [--repair] [--dry-run]
       ops install doctor

Ensures the repo-local ops package files and command scaffolding exist.
EOF
      exit 0
      ;;
    *) die "Unknown flag: ${_arg}. Use --help." ;;
  esac
done

_copy_if_missing() {
  local src="$1" dest="$2"
  if [[ -f "${dest}" ]]; then
    ops_ok "exists: ${dest#${OPS_PROJECT_ROOT}/}"
    return 0
  fi

  ops_info "create: ${dest#${OPS_PROJECT_ROOT}/}"
  if [[ "${DRY_RUN}" == "false" ]]; then
    mkdir -p "$(dirname "${dest}")"
    cp "${src}" "${dest}"
  fi
}

_ensure_dir() {
  local dir="$1"
  if [[ -d "${dir}" ]]; then
    ops_ok "dir: ${dir#${OPS_PROJECT_ROOT}/}"
    return 0
  fi

  ops_info "mkdir: ${dir#${OPS_PROJECT_ROOT}/}"
  [[ "${DRY_RUN}" == "true" ]] || mkdir -p "${dir}"
}

_doctor_install() {
  local fail=0
  for path in \
    "${OPS_PROJECT_ROOT}/ops.sh" \
    "${OPS_CORE_ROOT}/main.sh" \
    "${OPS_CORE_ROOT}/lib/init.sh" \
    "${OPS_CORE_ROOT}/lib/settings.sh" \
    "${OPS_PROJECT_ROOT}/.ops/templates/settings.json" \
    "${OPS_PROJECT_ROOT}/.ops/templates/setup.json" \
    "${OPS_PROJECT_ROOT}/.ops/schemas/settings.schema.json" \
    "${OPS_PROJECT_ROOT}/.ops/schemas/setup.schema.json" \
    "${OPS_PROJECT_ROOT}/.ops/schemas/profile.schema.json"; do
    if [[ -f "${path}" ]]; then
      ops_ok "found: ${path#${OPS_PROJECT_ROOT}/}"
    else
      ops_error "missing: ${path#${OPS_PROJECT_ROOT}/}"
      fail=$((fail + 1))
    fi
  done

  for dir in \
    "${OPS_PROJECT_ROOT}/.ops/commands"; do
    if [[ -d "${dir}" ]]; then
      ops_ok "dir: ${dir#${OPS_PROJECT_ROOT}/}"
    else
      ops_error "missing dir: ${dir#${OPS_PROJECT_ROOT}/}"
      fail=$((fail + 1))
    fi
  done

  return "${fail}"
}

ops_section "ops install"

if [[ "${SUBCMD}" == "doctor" ]]; then
  _doctor_install
  exit $?
fi

_ensure_dir "${OPS_PROJECT_ROOT}/.ops/commands"

if [[ "${REPAIR}" == "true" ]]; then
  ops_info "Repair mode checked core/template presence. Existing user config was not overwritten."
fi

ops_ok "Install check complete."
