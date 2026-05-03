#!/usr/bin/env bash
# .ops/core/commands/doctor.sh — System health check (Phase 0 partially implements this).
# This is the first command that gets meaningful behavior: it checks system
# prerequisites for the orchestrator itself without reading .ops.yaml.
# It is a READ-ONLY operation — safe to run at any time.
#
# Checks performed:
#   - bash version (4.3+ required for associative arrays + mapfile)
#   - required tools: yq, jq  (optional in Phase 0; warns if missing)
#   - OPS_PROJECT_ROOT resolved correctly
#   - .ops/core/ directory integrity
#   - .ops/ local dir writable (for future backups/locks)

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/init.sh
source "${_SELF_DIR}/../lib/init.sh"
# shellcheck source=../lib/logger.sh
source "${_SELF_DIR}/../lib/logger.sh"
# shellcheck source=../lib/settings.sh
source "${_SELF_DIR}/../lib/settings.sh"
# shellcheck source=../lib/setup.sh
source "${_SELF_DIR}/../lib/setup.sh"

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

# ── .ops/ local dir ─────────────────────────────────────────────────────────
_local="${OPS_PROJECT_ROOT}/.ops"
if [[ -d "${_local}" ]]; then
  if [[ -w "${_local}" ]]; then
    _check_pass ".ops/ local dir exists and is writable"
  else
    _check_fail ".ops/ local dir exists but is NOT writable"
  fi
else
  # Not yet created — that's fine in Phase 0 (created on first backup/lock)
  _check_warn ".ops/ local dir not yet created (created automatically on first mutating command)"
fi

# ── Optional tools ───────────────────────────────────────────────────────────
for _tool in yq jq; do
  if command -v "${_tool}" &>/dev/null; then
    _check_pass "${_tool} found: $(command -v "${_tool}")"
  else
    _check_warn "${_tool} not found — required by Phase 1 (manifest validation). Install: brew install ${_tool} / apt install ${_tool}"
  fi
done

# ── ops.sh reachable ─────────────────────────────────────────────────────────
if [[ -f "${OPS_PROJECT_ROOT}/ops.sh" ]]; then
  _check_pass "ops.sh found at project root"
else
  _check_warn "ops.sh not found at project root — expected for legacy compatibility"
fi

# ── Manifest (informational only — not required in Phase 0) ──────────────────
if [[ -f "${OPS_MANIFEST}" ]]; then
  _check_pass ".ops.yaml manifest exists"
else
  _check_warn ".ops.yaml not yet created (run 'ops experimental init' in Phase 2)"
fi

# ── Settings ─────────────────────────────────────────────────────────────────
if settings_exists; then
  if settings_validate >/dev/null 2>&1; then
    _check_pass ".ops.yaml settings section is valid"
  else
    _check_fail ".ops.yaml settings section is invalid"
  fi
else
  _check_warn ".ops.yaml not found for settings (built-in defaults will be used)"
fi

# ── Setup/Profile Config ─────────────────────────────────────────────────────
if setup_exists; then
  if setup_validate >/dev/null 2>&1; then
    _check_pass ".ops.yaml setup section is valid"
  else
    _check_fail ".ops.yaml setup section is invalid"
  fi
else
  _check_warn ".ops.yaml not found (run 'ops setup --apply')"
fi

if [[ -d "${OPS_PROJECT_STATE_DIR}" ]]; then
  _check_pass ".ops.project/ state directory exists"
else
  _check_warn ".ops.project/ not found (run 'ops setup --apply')"
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
