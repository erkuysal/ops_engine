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
#   bootstrap — Project config bootstrap from workspace metadata (LIVE)
#   validate  — Project config validator (LIVE)
#   env       — Environment broker: show/doctor subcommands (LIVE)
#   install   — Install/doctor/repair/uninstall global ops command (LIVE)
#   global    — Machine-global deployment profiles (LIVE)
#   setup     — Project setup/profile generation (LIVE)
#   ci        — CI/server credential readiness config (LIVE)
#   ssh       — Simple server SSH connection check (LIVE)
#   credentials — Local credential readiness check (LIVE)
#   init      — Interactive manifest wizard (LIVE)
#   run       — Single-service action runner (LIVE)
#   show      — Read-only action execution plan inspector (LIVE)
#   start     — Dependency-aware service start (LIVE)
#   stop      — Dependency-aware service stop (LIVE)
#   status    — Service runtime status (LIVE)
#   logs      — Multiplexed service logs (LIVE)
#   cleanup   — Remove stale generated runtime state (LIVE)
#   backup    — Snapshot project config (LIVE)
#   rollback  — Restore project config snapshot (LIVE)
#   package   — Inspect ops package checkout/install state (LIVE)
#   monitor   — Lightweight service/infra checks (LIVE)
#   ship      — Unified delivery pipeline planner (LIVE, execution pending)
#   build     — Native container build/push basics (LIVE)
#   deploy    — Native remote container deploy basics (LIVE)
#   update    — Manifest self-healing update (LIVE)
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
OPS_CORE_VERSION="0.12.0-phase9"
OPS_PACKAGE_MARKER="${_MAIN_DIR}/../../.ops-install-source"

# ── Help ─────────────────────────────────────────────────────────────────────
_usage() {
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    cat <<EOF
ops — orchestrator (${OPS_CORE_VERSION})

Usage: ops <command> [args...]

Commands:
  doctor    Check orchestrator prerequisites  [live]
            Use 'ops doctor boundaries' for package boundary checks.
  bootstrap Seed project config from probe-based workspace discovery [live]
  validate  Project config validator          [live]
  install   Install/doctor/repair global ops command [live]
  global    Manage machine-global deployment profiles [live]
  setup     Project setup/profile config      [live]
  ci        CI/server credential readiness     [live]
  ssh       Simple server SSH connection check [live]
  credentials Local credential readiness check [live]
  init      Interactive manifest wizard       [live]
  run       Single-service action runner      [live]
  show      Show how an action would run       [live]
  start     Dependency-aware start            [live]
  stop      Dependency-aware stop             [live]
  status    Service runtime status            [live]
  logs      Multiplexed logs stream           [live]
  cleanup   Preview/apply explicit cleanup categories [live]
  backup    Snapshot project config           [live]
  rollback  Restore project config snapshot   [live]
  package   Inspect ops package state         [live]
  monitor   Lightweight service/infra checks  [live]
  ship      Unified delivery pipeline planner [live, plan-only]
  build     Native container build/push       [live]
  deploy    Native remote container deploy    [live]
  update    Manifest self-healing update      [live]
  env       show/doctor env context           [live]
  version   Print version
  help      Print this help

Flags:
  OPS_DEBUG=true    Enable debug/trace output
  OPS_PLAIN=true    Disable colors (CI mode)
  --dry-run         Preview without making changes (where supported)

Settings:
  .ops.project/config/ Primary project configuration
  .ops.project/        Generated runtime state (logs, pids, backups, secrets)
  .ops.yaml            Optional compatibility import/export

Docs:
  CONTRIBUTING.md     Contributor guide
  docs/README.md      Package documentation index

EOF
  else
    cat <<EOF

${OPS_BOLD}ops${OPS_NC} ${OPS_DIM}— orchestrator ${OPS_CORE_VERSION}${OPS_NC}

${OPS_BOLD}Usage:${OPS_NC} ${OPS_DIM}./ops.sh <command> [args...]${OPS_NC}

${OPS_BOLD}Commands${OPS_NC}
  ${OPS_BOLD}doctor${OPS_NC}    Check orchestrator prerequisites     ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_DIM}          doctor boundaries checks package/project separation${OPS_NC}
  ${OPS_BOLD}bootstrap${OPS_NC} Seed project config from discovery  ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}validate${OPS_NC}  Project config validator            ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}install${OPS_NC}   Install/doctor/repair global command ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}global${OPS_NC}    Machine-global deployment profiles  ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}setup${OPS_NC}     Project setup/profile config         ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}ci${OPS_NC}        CI/server credential readiness        ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}ssh${OPS_NC}       Simple server SSH connection check    ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}credentials${OPS_NC} Local credential readiness check     ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}init${OPS_NC}      Interactive manifest wizard       ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}run${OPS_NC}       Single-service action runner      ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}show${OPS_NC}      Show how an action would run       ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}start${OPS_NC}     Dependency-aware start            ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}status${OPS_NC}    Service runtime status (PIDs)      ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}stop${OPS_NC}      Dependency-aware stop             ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}logs${OPS_NC}      Multiplexed logs stream           ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}cleanup${OPS_NC}   Preview/apply cleanup categories  ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}backup${OPS_NC}    Snapshot project config           ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}rollback${OPS_NC}  Restore project config snapshot   ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}package${OPS_NC}   Inspect ops package state         ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}monitor${OPS_NC}   Lightweight service/infra checks  ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}ship${OPS_NC}      Unified delivery pipeline planner ${OPS_YELLOW}[live, plan-only]${OPS_NC}
  ${OPS_BOLD}build${OPS_NC}     Native container build/push       ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}deploy${OPS_NC}    Native remote container deploy    ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}update${OPS_NC}    Manifest self-healing update      ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}env${OPS_NC}       show / doctor env context          ${OPS_GREEN}[live]${OPS_NC}
  ${OPS_BOLD}version${OPS_NC}   Print version
  ${OPS_BOLD}help${OPS_NC}      Print this help

${OPS_BOLD}Flags${OPS_NC}
  ${OPS_DIM}OPS_DEBUG=true    Enable debug/trace output${OPS_NC}
  ${OPS_DIM}OPS_PLAIN=true    Disable colors (CI mode)${OPS_NC}
  ${OPS_DIM}--dry-run         Preview without making changes (where supported)${OPS_NC}

${OPS_BOLD}Settings${OPS_NC}
  ${OPS_DIM}.ops.project/config/ Primary project configuration${OPS_NC}
  ${OPS_DIM}.ops.project/        Generated runtime state (logs, pids, backups, secrets)${OPS_NC}
  ${OPS_DIM}.ops.yaml            Optional compatibility import/export${OPS_NC}

${OPS_BOLD}Docs${OPS_NC}
  ${OPS_DIM}CONTRIBUTING.md     Contributor guide${OPS_NC}
  ${OPS_DIM}docs/README.md      Package documentation index${OPS_NC}

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

  global)
    exec bash "${_MAIN_DIR}/commands/global.sh" "$@"
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

  status|ps)
    exec bash "${_MAIN_DIR}/commands/status.sh" "$@"
    ;;

  logs)
    exec bash "${_MAIN_DIR}/commands/logs.sh" "$@"
    ;;

  cleanup|clean)
    exec bash "${_MAIN_DIR}/commands/cleanup.sh" "$@"
    ;;

  backup)
    exec bash "${_MAIN_DIR}/commands/backup.sh" "$@"
    ;;

  rollback)
    exec bash "${_MAIN_DIR}/commands/rollback.sh" "$@"
    ;;

  package)
    exec bash "${_MAIN_DIR}/commands/package.sh" "$@"
    ;;

  monitor)
    exec bash "${_MAIN_DIR}/commands/monitor.sh" "$@"
    ;;

  ship)
    exec bash "${_MAIN_DIR}/commands/ship.sh" "$@"
    ;;

  build)
    exec bash "${_MAIN_DIR}/commands/build.sh" "$@"
    ;;

  deploy)
    exec bash "${_MAIN_DIR}/commands/deploy.sh" "$@"
    ;;

  update)
    exec bash "${_MAIN_DIR}/commands/update.sh" "$@"
    ;;

  env)
    exec bash "${_MAIN_DIR}/commands/env.sh" "$@"
    ;;

  *)
    ops_error "Unknown experimental command: '${COMMAND}'"
    _usage
    exit 1
    ;;
esac
