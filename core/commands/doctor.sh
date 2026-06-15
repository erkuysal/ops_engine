#!/usr/bin/env bash
# .ops/core/commands/doctor.sh — System health check (Phase 0 partially implements this).
# This is the first command that gets meaningful behavior: it checks system
# prerequisites for the orchestrator itself without requiring .ops.yaml.
# It is a READ-ONLY operation — safe to run at any time.
#
# Checks performed:
#   - bash version (4.3+ required for associative arrays + mapfile)
#   - required tools: yq, jq  (optional in Phase 0; warns if missing)
#   - OPS_PROJECT_ROOT resolved correctly
#   - .ops/core/ directory integrity
#   - .ops/ package directory integrity
#   - .ops.project/ state directory availability

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/init.sh
source "${_SELF_DIR}/../lib/init.sh"
# shellcheck source=../lib/logger.sh
source "${_SELF_DIR}/../lib/logger.sh"
# shellcheck source=../lib/manifest.sh
source "${_SELF_DIR}/../lib/manifest.sh"
# shellcheck source=../lib/settings.sh
source "${_SELF_DIR}/../lib/settings.sh"
# shellcheck source=../lib/setup.sh
source "${_SELF_DIR}/../lib/setup.sh"

if [[ "${1:-}" == "boundaries" || "${1:-}" == "boundary" ]]; then
  # shellcheck source=../lib/boundaries.sh
  source "${_SELF_DIR}/../lib/boundaries.sh"
  boundary_doctor
  exit $?
fi

_PASS=0
_WARN=0
_FAIL=0

_check_pass() { ops_ok    "  ✔  $*"; _PASS=$((_PASS+1)); }
_check_warn() { ops_warn  "  ⚠   $*"; _WARN=$((_WARN+1)); }
_check_fail() { ops_error "  ✘  $*"; _FAIL=$((_FAIL+1)); }

ops_section "ops experimental doctor"
ops_info "Checking orchestrator prerequisites..."
printf '\n'

# ── Bash version ────────────────────────────────────────────────────────────
_bash_major="${BASH_VERSINFO[0]:-0}"
_bash_minor="${BASH_VERSINFO[1]:-0}"
if (( _bash_major > 4 || ( _bash_major == 4 && _bash_minor >= 3 ) )); then
  _check_pass "bash ${BASH_VERSION} (≥ 4.3 required)"
else
  _check_fail "bash ${BASH_VERSION} — need 4.3+. Install a newer bash (brew install bash / apt install bash)."
fi

# ── Project root ─────────────────────────────────────────────────────────────
if [[ -n "${OPS_PROJECT_ROOT:-}" && -d "${OPS_PROJECT_ROOT}" ]]; then
  _check_pass "OPS_PROJECT_ROOT resolved → ${OPS_PROJECT_ROOT}"
else
  _check_fail "OPS_PROJECT_ROOT could not be resolved. Run from within the project directory."
fi

# ── .ops/core/ integrity ─────────────────────────────────────────────────────
_core="${OPS_CORE_ROOT}"
if [[ -d "${_core}" ]]; then
  _check_pass ".ops/core/ directory exists"
else
  _check_fail ".ops/core/ missing. Re-run Phase 0 scaffold."
fi

_required_libs=(init.sh logger.sh backup.sh manifest.sh env.sh settings.sh setup.sh)
for _lib in "${_required_libs[@]}"; do
  if [[ -f "${_core}/lib/${_lib}" ]]; then
    _check_pass ".ops/core/lib/${_lib}"
  else
    _check_fail ".ops/core/lib/${_lib} missing"
  fi
done

# ── package dir ──────────────────────────────────────────────────────────────
_local="$(dirname "${OPS_CORE_ROOT}")"
if [[ -d "${_local}" ]]; then
  _check_pass ".ops/ package directory exists (${_local})"
else
  _check_fail ".ops/ package directory missing (${_local})"
fi

# ── .ops.project/ state dir ─────────────────────────────────────────────────
if [[ -d "${OPS_PROJECT_STATE_DIR}" ]]; then
  if [[ -w "${OPS_PROJECT_STATE_DIR}" ]]; then
    _check_pass ".ops.project/ state directory exists and is writable"
  else
    _check_fail ".ops.project/ state directory exists but is NOT writable"
  fi
else
  _check_warn ".ops.project/ state directory not yet created (run 'ops setup --apply')"
fi

# ── Optional tools ───────────────────────────────────────────────────────────
for _tool in yq jq; do
  if command -v "${_tool}" &>/dev/null; then
    _check_pass "${_tool} found: $(command -v "${_tool}")"
  else
    _check_warn "${_tool} not found — required for project config validation. Install: brew install ${_tool} / apt install ${_tool}"
  fi
done

# ── ops.sh reachable ─────────────────────────────────────────────────────────
if [[ -f "${OPS_PROJECT_ROOT}/ops.sh" ]]; then
  _check_pass "ops.sh found at project root"
else
  _check_warn "ops.sh not found at project root — expected for legacy compatibility"
fi

# ── Manifest (informational only — not required in Phase 0) ──────────────────
if project_config_services_exists; then
  _check_pass ".ops.project/config/services.json exists"
else
  _check_warn ".ops.project/config not yet created (run 'ops setup --apply')"
fi

if [[ -f "${OPS_MANIFEST}" ]]; then
  _check_pass ".ops.yaml compatibility export exists"
else
  if project_config_services_exists; then
    _check_pass ".ops.yaml compatibility export not present (optional)"
  else
    _check_warn ".ops.yaml compatibility export not present"
  fi
fi

if project_config_services_exists && [[ -f "${OPS_MANIFEST}" ]] && command -v yq >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  yaml_services_count="$(yq e '.services | length' "${OPS_MANIFEST}" 2>/dev/null || printf '')"
  config_services_count="$(jq -r '.services | length' "${OPS_PROJECT_CONFIG_SERVICES_FILE}" 2>/dev/null || printf '')"
  if [[ -n "${yaml_services_count}" && -n "${config_services_count}" && "${yaml_services_count}" == "${config_services_count}" ]]; then
    _check_pass "YAML compatibility export service count matches project config"
  else
    _check_warn "YAML compatibility export may be out of sync with project config; run 'ops setup export-yaml --apply' if needed"
  fi
fi

# ── Settings ─────────────────────────────────────────────────────────────────
if settings_exists; then
  if settings_validate >/dev/null 2>&1; then
    _check_pass "settings config is valid"
  else
    _check_fail "settings config is invalid"
  fi
else
  _check_warn "settings config not found (built-in defaults will be used)"
fi

# ── Setup/Profile Config ─────────────────────────────────────────────────────
if setup_exists; then
  if setup_validate >/dev/null 2>&1; then
    _check_pass "setup config is valid"
  else
    _check_fail "setup config is invalid"
  fi
else
  _check_warn "setup config not found (run 'ops setup --apply')"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n'
if [[ "${OPS_PLAIN}" == "true" ]]; then
  printf 'Doctor summary: %d passed, %d warnings, %d failed\n' "${_PASS}" "${_WARN}" "${_FAIL}"
else
  printf '%s' "${OPS_BOLD}"
  printf 'Doctor summary: %s%d passed%s  %s%d warnings%s  %s%d failed%s\n' \
    "${OPS_GREEN}" "${_PASS}" "${OPS_NC}${OPS_BOLD}" \
    "${OPS_YELLOW}" "${_WARN}" "${OPS_NC}${OPS_BOLD}" \
    "${OPS_RED}" "${_FAIL}" "${OPS_NC}"
fi

if (( _FAIL > 0 )); then
  exit 1
fi
exit 0
