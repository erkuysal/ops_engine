#!/usr/bin/env bash
# .ops-core/main.sh — Orchestrator entrypoint. Called by ops.sh via `ops experimental ...`.
#
# Usage (via ops.sh gate):
#   ./ops.sh experimental <command> [args...]
#   ./ops.sh experimental --help
#
# Direct invocation (for debugging):
#   bash .ops-core/main.sh <command> [args...]
#
# Available commands:
#   doctor    — System prerequisites check (LIVE)
#   bootstrap — One-shot .ops.yaml generator from project metadata (LIVE)
#   validate  — Four-pass manifest validator (LIVE)
#   env       — Environment broker: show/doctor subcommands (LIVE)
#   install   — Install/doctor/repair/uninstall global ops command (LIVE)
#   setup     — Project setup/profile generation (LIVE)
#   ci        — CI/server credential readiness config (LIVE)
#   ssh       — Simple server SSH connection check (LIVE)
#   credentials — Local credential readiness check (LIVE)
#   init      — Interactive manifest wizard (Phase 2)
#   run       — Single-service action runner (Phase 3)
#   show      — Read-only action execution plan inspector (LIVE)
#   start     — Dependency-aware service start (Phase 4)
#   stop      — Dependency-aware service stop (Phase 5)
#   logs      — Multiplexed service logs (Phase 5)
#   update    — Manifest self-healing update (Phase 7)
#   version   — Print orchestrator version
#   help      — Print this help

set -euo pipefail

_MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Bootstrap ────────────────────────────────────────────────────────────────
# Set OPS_PROJECT_ROOT early so lib/init.sh path resolvers pick it up.
# When called from ops.sh, PROJECT_ROOT is already in the environment.
if [[ -z "${OPS_PROJECT_ROOT:-}" ]]; then
  OPS_PROJECT_ROOT="$(cd "${_MAIN_DIR}/../.." && pwd)"
  export OPS_PROJECT_ROOT
fi

# shellcheck source=lib/init.sh
source "${_MAIN_DIR}/lib/init.sh"
# shellcheck source=lib/logger.sh
source "${_MAIN_DIR}/lib/logger.sh"

# ── Version ──────────────────────────────────────────────────────────────────
OPS_CORE_VERSION="0.11.0-phase9"
OPS_PACKAGE_MARKER="${_MAIN_DIR}/../../.ops-install-source"

# ── Help ─────────────────────────────────────────────────────────────────────
_usage() {
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    cat <<EOF
ops — orchestrator (${OPS_CORE_VERSION})

Usage: ops <command> [args...]

Commands:
  doctor    Check orchestrator prerequisites  [live]
  bootstrap Seed .ops.yaml from probe-based workspace discovery [live]
  validate  Manifest validator                [live]
  install   Install/doctor/repair global ops command [live]
  setup     Project setup/profile config      [live]
  ci        CI/server credential readiness     [live]
  ssh       Simple server SSH connection check [live]
  credentials Local credential readiness check [live]
  init      Interactive manifest wizard       [Phase 2]
  run       Single-service action runner      [Phase 3]
  show      Show how an action would run       [live]
  start     Dependency-aware start            [Phase 4]
  stop      Dependency-aware stop             [Phase 5]
  logs      Multiplexed logs stream           [Phase 5]
  update    Manifest self-healing update      [Phase 7]
  env       show/doctor env context           [live]
  version   Print version
  help      Print this help

Flags:
  OPS_DEBUG=true    Enable debug/trace output
  OPS_PLAIN=true    Disable colors (CI mode)
  --dry-run         Preview without making changes (where supported)

Settings:
  .ops.yaml           Project-specific settings/setup/profiles
  .ops.project/       Generated runtime state (logs, pids, backups)

EOF
  else
    cat <<EOF

${OPS_BOLD}ops${OPS_NC} ${OPS_DIM}— orchestrator ${OPS_CORE_VERSION}${OPS_NC}

${OPS_BOLD}Usage:${OPS_NC} ${OPS_DIM}./ops.sh <command> [args...]${OPS_NC}

${OPS_BOLD}Commands${OPS_NC}
  ${OPS_BOLD}doctor${OPS_NC}    Check orchestrator prerequisites     ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}bootstrap${OPS_NC} Seed .ops.yaml from probe-based discovery ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}validate${OPS_NC}  Manifest validator                   ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}install${OPS_NC}   Install/doctor/repair global command ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}setup${OPS_NC}     Project setup/profile config         ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}ci${OPS_NC}        CI/server credential readiness        ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}ssh${OPS_NC}       Simple server SSH connection check    ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}credentials${OPS_NC} Local credential readiness check     ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_DIM}init      Interactive manifest wizard          [Phase 2]${OPS_NC}
  ${OPS_DIM}run       Single-service action runner         [Phase 3]${OPS_NC}
  ${OPS_BOLD}show${OPS_NC}      Show how an action would run       ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_DIM}start     Dependency-aware start               [Phase 4]${OPS_NC}
  ${OPS_DIM}update    Manifest self-healing update         [Phase 7]${OPS_NC}
  ${OPS_BOLD}env${OPS_NC}       show / doctor env context          ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}version${OPS_NC}   Print version
  ${OPS_BOLD}help${OPS_NC}      Print this help

${OPS_BOLD}Flags${OPS_NC}
  ${OPS_DIM}OPS_DEBUG=true    Enable debug/trace output${OPS_NC}
  ${OPS_DIM}OPS_PLAIN=true    Disable colors (CI mode)${OPS_NC}
  ${OPS_DIM}--dry-run         Preview without making changes (where supported)${OPS_NC}

${OPS_BOLD}Settings${OPS_NC}
  ${OPS_DIM}.ops.yaml           Project-specific settings/setup/profiles${OPS_NC}
  ${OPS_DIM}.ops.project/       Generated runtime state (logs, pids, backups)${OPS_NC}

${OPS_DIM}Project root: ${OPS_PROJECT_ROOT}${OPS_NC}

EOF
  fi
}

# ── Argument parsing ─────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  _usage
  exit 0
fi

COMMAND="${1}"
shift

case "${COMMAND}" in
  help|--help|-h)
    _usage
    exit 0
    ;;

  version|--version|-v)
    printf 'ops-core %s\n' "${OPS_CORE_VERSION}"
    if [[ -f "${OPS_PACKAGE_MARKER}" ]]; then
      sed -n 's/^ops-core-version=/installed-package-version /p; s/^source-revision=/installed-source-revision /p; s/^updated-at=/installed-updated-at /p' "${OPS_PACKAGE_MARKER}" 2>/dev/null
    fi
    exit 0
    ;;

  doctor)
    # shellcheck source=commands/doctor.sh
    exec bash "${_MAIN_DIR}/commands/doctor.sh" "$@"
    ;;

  bootstrap)
    exec bash "${_MAIN_DIR}/commands/bootstrap.sh" "$@"
    ;;

  validate)
    exec bash "${_MAIN_DIR}/commands/validate.sh" "$@"
    ;;

  install)
    exec bash "${_MAIN_DIR}/commands/install.sh" "$@"
    ;;

  setup)
    exec bash "${_MAIN_DIR}/commands/setup.sh" "$@"
    ;;

  ci)
    exec bash "${_MAIN_DIR}/commands/ci.sh" "$@"
    ;;

  ssh)
    if [[ "${1:-}" == "setup" ]]; then
      shift
      exec bash "${_MAIN_DIR}/commands/ci.sh" ssh-setup "$@"
    fi
    exec bash "${_MAIN_DIR}/commands/ci.sh" connect "$@"
    ;;

  credentials|creds)
    exec bash "${_MAIN_DIR}/commands/ci.sh" credentials "$@"
    ;;

  init)
    exec bash "${_MAIN_DIR}/commands/init.sh" "$@"
    ;;

  run)
    exec bash "${_MAIN_DIR}/commands/run.sh" "$@"
    ;;

  show)
    exec bash "${_MAIN_DIR}/commands/show.sh" "$@"
    ;;

  start)
    exec bash "${_MAIN_DIR}/commands/start.sh" "$@"
    ;;

  stop)
    exec bash "${_MAIN_DIR}/commands/stop.sh" "$@"
    ;;

  logs)
    exec bash "${_MAIN_DIR}/commands/logs.sh" "$@"
    ;;

  update)
    exec bash "${_MAIN_DIR}/commands/update.sh" "$@"
    ;;

  env)
    exec bash "${_MAIN_DIR}/commands/env.sh" "$@"
    ;;

  run)
    exec bash "${_MAIN_DIR}/commands/run.sh" "$@"
    ;;

  *)
    ops_error "Unknown experimental command: '${COMMAND}'"
    _usage
    exit 1
    ;;
esac
