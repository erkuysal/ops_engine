#!/usr/bin/env bash
# .ops-core/lib/interactive.sh — Reusable prompt primitives for wizard flows.
#
# All prompts are written to /dev/tty directly so they don't pollute stdout.
# Return values (user choices) always go to stdout — callers can capture them.
#
# CI guard: ops commands that require interaction must call interactive_require_tty
# at entry. All primitives also call it defensively.
#
# Requires: init.sh, logger.sh (sourced first)

set -euo pipefail
if [[ "${_OPS_CORE_INTERACTIVE_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_INTERACTIVE_LOADED=1

# ============================================================================
# TTY GUARD
# ============================================================================

# Abort with a clear message if running in CI or without a terminal.
# Call at the top of any command that requires interaction.
interactive_require_tty() {
  if [[ "${OPS_CI:-false}" == "true" ]]; then
    die "This command requires an interactive terminal. OPS_CI=true detected.
  Use --dry-run for non-interactive preview." 2
  fi
  if [[ ! -t 0 ]]; then
    die "This command requires an interactive terminal (stdin is not a tty).
  Use --dry-run for non-interactive preview." 2
  fi
}

# ============================================================================
# MENU
# ============================================================================

# Display a numbered menu and return the 0-based index of the chosen item.
# Repeats until a valid number is entered.
#
# Usage:   idx="$(interactive_menu "Choose stack:" "django" "node" "custom")"
# Prints:  0  (for "django")
interactive_menu() {
  local prompt="$1"
  shift
  local -a options=("$@")
  local total="${#options[@]}"

  interactive_require_tty

  {
    printf '\n%s\n' "${prompt}"
    local i=1
    local opt
    for opt in "${options[@]}"; do
      printf '  %d) %s\n' "${i}" "${opt}"
      i=$((i + 1))
    done
  } > /dev/tty

  local choice
  while true; do
    printf 'Enter number [1-%d]: ' "${total}" > /dev/tty
    read -r choice < /dev/tty
    if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )); then
      printf '%d' $((choice - 1))
      return 0
    fi
    printf 'Please enter a number between 1 and %d.\n' "${total}" > /dev/tty
  done
}

# ============================================================================
# YES / NO
# ============================================================================

# Prompt for yes/no. Returns 0 for yes, 1 for no.
# Default is used when the user presses Enter without input.
#
# Usage:   interactive_confirm "Add this service?" y
# Default: n
interactive_confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-n}"

  interactive_require_tty

  local suffix="[y/N]"
  [[ "${default}" == "y" ]] && suffix="[Y/n]"

  printf '\n%s %s: ' "${prompt}" "${suffix}" > /dev/tty
  local reply
  read -r reply < /dev/tty
  [[ -z "${reply}" ]] && reply="${default}"
  case "${reply,,}" in
    y|yes) return 0 ;;
    *)     return 1 ;;
  esac
}

# ============================================================================
# FREE TEXT
# ============================================================================

# Prompt for a free-form text value with an optional default.
# Prints the chosen value to stdout.
#
# Usage:   name="$(interactive_prompt "Service name" "backend")"
interactive_prompt() {
  local prompt="$1"
  local default="${2:-}"

  interactive_require_tty

  if [[ -n "${default}" ]]; then
    printf '%s [%s]: ' "${prompt}" "${default}" > /dev/tty
  else
    printf '%s: ' "${prompt}" > /dev/tty
  fi

  local reply
  read -r reply < /dev/tty
  if [[ -z "${reply}" && -n "${default}" ]]; then
    printf '%s' "${default}"
  else
    printf '%s' "${reply}"
  fi
}

# ============================================================================
# LIST PROMPT (space-separated, validated)
# ============================================================================

# Prompt for a space-separated list of IDs, validated against a known set.
# Prints the validated reply to stdout (may be empty).
#
# Usage:   deps="$(interactive_list_prompt "depends_on" "backend voice_app go" "")"
interactive_list_prompt() {
  local prompt="$1"
  local valid_ids="$2"      # space-separated list of valid IDs
  local default="${3:-}"    # pre-filled default (may be empty)

  interactive_require_tty

  if [[ -n "${default}" ]]; then
    printf '\n%s\n  (space-separated, valid: %s)\n  [%s]: ' \
      "${prompt}" "${valid_ids}" "${default}" > /dev/tty
  else
    printf '\n%s\n  (space-separated, valid: %s, or press Enter for none): ' \
      "${prompt}" "${valid_ids}" > /dev/tty
  fi

  local reply
  read -r reply < /dev/tty
  [[ -z "${reply}" ]] && reply="${default}"

  # Validate each entry
  if [[ -n "${reply}" ]]; then
    local item bad=false
    for item in ${reply}; do
      if ! printf ' %s ' "${valid_ids}" | grep -qF " ${item} "; then
        printf "  Unknown id: '%s'. Valid options: %s\n" "${item}" "${valid_ids}" > /dev/tty
        bad=true
      fi
    done
    if [[ "${bad}" == "true" ]]; then
      # Re-prompt
      interactive_list_prompt "${prompt}" "${valid_ids}" "${reply}"
      return
    fi
  fi

  printf '%s' "${reply}"
}

# ============================================================================
# DISPLAY HELPERS
# ============================================================================

# Print a section banner to tty (not logged — just visual separation in wizard)
interactive_banner() {
  local msg="$*"
  printf '\n%s━━━ %s ━━━%s\n' "${OPS_BOLD}" "${msg}" "${OPS_NC}" > /dev/tty
}
