#!/usr/bin/env bash
# .ops-core/lib/output.sh — Shared JSON --json envelope for commands.
#
# Every "ops <command> --json" output gets `ok` (bool) and `command` (string)
# merged in at the top level, alongside whatever fields the command already
# returns. This is additive, not a rewrite: existing consumers that read a
# known field directly (e.g. `package --json | jq .git.branch`) keep working
# unchanged; a caller (human or agent) that only wants to know "did this
# succeed, and what command produced it" now has one stable place to look
# instead of a different shape per command.
#
# `ok` reflects that JSON was successfully produced, not full command
# success in every sense — a command that dies before reaching its JSON
# block still exits non-zero with a plain-text [ERROR] line on stderr, not
# JSON. See schemas/command-result.schema.json for the contract this
# guarantees, and docs/reference/json-output.md for which commands support
# --json today.
#
# Usage: pipe an already-built JSON object through this.
#   jq -n --arg tag "${TAG}" '{tag: $tag}' | ops_json_envelope "build"
#
# Requires: init.sh (sourced first) for require_bins.

if [[ "${_OPS_CORE_OUTPUT_LOADED:-}" == "1" ]]; then
  return 0
fi
_OPS_CORE_OUTPUT_LOADED=1

# Usage: ops_json_envelope COMMAND [OK]
# Reads a JSON object on stdin, merges {ok: OK, command: COMMAND} into it,
# and prints the result. OK defaults to true (reaching this call already
# implies the command's own JSON construction succeeded).
ops_json_envelope() {
  local command="${1:?ops_json_envelope: command name required}"
  local ok="${2:-true}"
  require_bins jq
  jq --arg command "${command}" --argjson ok "${ok}" '. + {ok: $ok, command: $command}'
}
