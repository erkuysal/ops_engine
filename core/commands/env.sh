#!/usr/bin/env bash
# .ops-core/commands/env.sh — env show / env doctor subcommands.
#
# Usage:
#   ./ops.sh experimental env show   <service-id> [--unmask] [--ci-mode]
#   ./ops.sh experimental env show   --all        [--unmask] [--ci-mode]
#   ./ops.sh experimental env doctor <service-id>
#   ./ops.sh experimental env --help

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/init.sh
source "${_SELF_DIR}/../lib/init.sh"
# shellcheck source=../lib/logger.sh
source "${_SELF_DIR}/../lib/logger.sh"
# shellcheck source=../lib/manifest.sh
source "${_SELF_DIR}/../lib/manifest.sh"
# shellcheck source=../lib/env.sh
source "${_SELF_DIR}/../lib/env.sh"

# ── Usage ─────────────────────────────────────────────────────────────────────
_usage_env() {
  if [[ "${OPS_PLAIN}" == "true" ]]; then
    cat <<'EOF'
ops experimental env — environment broker utilities

Usage: ops experimental env <subcommand> [args...]

Subcommands:
  show   <service-id> [--unmask] [--ci-mode]
         Show resolved env key provenance for a service.
         Sensitive values are masked unless --unmask is passed.

  show   --all [--unmask] [--ci-mode]
         Show env context for every service in the manifest.

  doctor <service-id>
         Diagnose missing files, unreadable files, and policy mismatches.

Flags:
  --unmask    Show actual values for sensitive keys (use with care)
  --ci-mode   Simulate CI behaviour (skip local-only env files)
  --help      Print this help

Examples:
  ./ops.sh experimental env show backend
  ./ops.sh experimental env show --all --unmask
  ./ops.sh experimental env doctor <service-id>
  OPS_CI=true ./ops.sh experimental env show backend
EOF
  else
    cat <<EOF

${OPS_BOLD}ops experimental env${OPS_NC} ${OPS_DIM}— environment broker utilities${OPS_NC}

${OPS_BOLD}Usage:${OPS_NC} ${OPS_DIM}ops experimental env <subcommand> [args...]${OPS_NC}

${OPS_BOLD}Subcommands${OPS_NC}
  ${OPS_BOLD}show${OPS_NC}   ${OPS_DIM}<service-id>${OPS_NC}  Show resolved env key provenance (values masked)
  ${OPS_BOLD}show${OPS_NC}   ${OPS_DIM}--all${OPS_NC}         Show env context for every service
  ${OPS_BOLD}doctor${OPS_NC} ${OPS_DIM}<service-id>${OPS_NC}  Diagnose missing files and policy issues

${OPS_BOLD}Flags${OPS_NC}
  ${OPS_DIM}--unmask     Show actual sensitive values${OPS_NC}
  ${OPS_DIM}--ci-mode    Simulate CI skip behaviour${OPS_NC}
  ${OPS_DIM}--help       Print this help${OPS_NC}

EOF
  fi
}

# ── Argument parsing ──────────────────────────────────────────────────────────
SUBCMD="${1:-}"
shift || true

case "${SUBCMD}" in
  help|--help|-h|"")
    _usage_env
    exit 0
    ;;
esac

require_manifest_or_config

# ── show ──────────────────────────────────────────────────────────────────────
if [[ "${SUBCMD}" == "show" ]]; then
  service_id=""
  show_all=false
  unmask_flag=""
  ci_flag=""

  for _arg in "$@"; do
    case "${_arg}" in
      --all)      show_all=true ;;
      --unmask)   unmask_flag="--unmask" ;;
      --ci-mode)  ci_flag="--ci-mode" ;;
      --*)        die "Unknown flag: ${_arg}. Use --help for usage." ;;
      *)          service_id="${_arg}" ;;
    esac
  done

  if [[ "${show_all}" == "true" ]]; then
    ops_section "ops experimental env show --all"
    mapfile -t _ALL_SVCS < <(manifest_list_services)
    for svc in "${_ALL_SVCS[@]+"${_ALL_SVCS[@]}"}"; do
      printf '\n'
      if [[ "${OPS_PLAIN}" == "true" ]]; then
        printf '--- service: %s ---\n' "${svc}"
      else
        printf '%s--- service: %s ---%s\n' "${OPS_BOLD}" "${svc}" "${OPS_NC}"
      fi
      # shellcheck disable=SC2086
      env_show_context "${svc}" ${unmask_flag} ${ci_flag}
    done
    printf '\n'
  elif [[ -n "${service_id}" ]]; then
    ops_section "ops experimental env show: ${service_id}"
    manifest_service_exists "${service_id}" || \
      die "Unknown service id: '${service_id}'. Run 'ops experimental validate' to see declared services."
    printf '\n'
    # shellcheck disable=SC2086
    env_show_context "${service_id}" ${unmask_flag} ${ci_flag}
    printf '\n'
  else
    ops_error "Usage: ops experimental env show <service-id>  OR  ops experimental env show --all"
    exit 1
  fi

# ── doctor ────────────────────────────────────────────────────────────────────
elif [[ "${SUBCMD}" == "doctor" ]]; then
  service_id="${1:-}"
  [[ -z "${service_id}" ]] && {
    ops_error "Usage: ops experimental env doctor <service-id>"
    exit 1
  }

  manifest_service_exists "${service_id}" || \
    die "Unknown service id: '${service_id}'. Run 'ops experimental validate' to see declared services."

  ops_section "ops experimental env doctor: ${service_id}"
  printf '\n'
  env_doctor_check "${service_id}"

# ── unknown subcommand ────────────────────────────────────────────────────────
else
  ops_error "Unknown env subcommand: '${SUBCMD}'"
  _usage_env
  exit 1
fi
