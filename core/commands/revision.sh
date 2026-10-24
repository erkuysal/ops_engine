#!/usr/bin/env bash
# .ops/core/commands/revision.sh - Deploy revision records and deployment history.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unset OPS_PROJECT_CONFIG_DIR OPS_PROJECT_CONFIG_SERVICES_FILE OPS_PROJECT_CONFIG_PROJECT_FILE
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/output.sh"
source "${_SELF_DIR}/../lib/container_pipeline.sh"
source "${_SELF_DIR}/../lib/revision.sh"

_usage_revision() {
  cat <<'EOF'
Usage: ops revision <show|record|current|history> [flags]

Record what was deployed, when, by whom and where. Works with or without git.

  show      Print the record a deploy would write now (read-only)
  record    Append a record to the local history; with --remote, also write it to
            the server (DEPLOY_PATH/.ops-revision.json and .ops-deploys.jsonl)
  current   Print the record on the server and compare it with this checkout
  history   List recorded deploys, newest first (local, or --remote)

Flags:
  --message=TEXT, -m TEXT  What is being deployed (asked for when there is no git)
  --target=NAME            Environment label, e.g. staging or prod
  --allow-dirty            Record even with uncommitted git changes (marked dirty)
  --remote                 Use the deploy server (record/current/history)
  --path=DIR               Deploy path on the server (default: DEPLOY_PATH / ci.json)
  --limit=N                History entries to show (default 20)
  --non-interactive        Never prompt
  --dry-run                record: print what would be written, write nothing
  --json                   Machine-readable output

The server connection comes from .ops.project/config/ci.json and
.ops.project/secrets/ci.env; DEPLOY_HOST, DEPLOY_USER, DEPLOY_PATH and
DEPLOY_SSH_KEY_PATH override it.
EOF
}

SUBCOMMAND="${1:-}"
case "${SUBCOMMAND}" in
  show|record|current|history) shift ;;
  --help|-h|help) _usage_revision; exit 0 ;;
  "") _usage_revision; exit 2 ;;
  *) die "Unknown revision subcommand: ${SUBCOMMAND} (expected show, record, current or history)" 2 ;;
esac

MESSAGE=""
TARGET=""
ALLOW_DIRTY=false
REMOTE=false
REMOTE_PATH=""
LIMIT=20
NON_INTERACTIVE=false
DRY_RUN=false
JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message=*) MESSAGE="${1#*=}" ;;
    --message|-m)
      [[ $# -ge 2 ]] || die "$1 requires a value" 2
      MESSAGE="$2"
      shift
      ;;
    --target=*) TARGET="${1#*=}" ;;
    --target)
      [[ $# -ge 2 ]] || die "--target requires a value" 2
      TARGET="$2"
      shift
      ;;
    --allow-dirty) ALLOW_DIRTY=true ;;
    --remote) REMOTE=true ;;
    --path=*) REMOTE_PATH="${1#*=}" ;;
    --limit=*) LIMIT="${1#*=}" ;;
    --non-interactive) NON_INTERACTIVE=true ;;
    --dry-run) DRY_RUN=true ;;
    --json) JSON=true ;;
    --help|-h) _usage_revision; exit 0 ;;
    *) die "Unknown revision flag: $1" 2 ;;
  esac
  shift
done

require_bins jq
[[ "${LIMIT}" =~ ^[1-9][0-9]*$ ]] || die "--limit must be a positive integer" 2

_can_prompt() {
  [[ "${NON_INTERACTIVE}" != "true" &&
     "${OPS_NON_INTERACTIVE:-false}" != "true" &&
     "${CI:-false}" != "true" &&
     "${JSON}" != "true" &&
     -t 0 ]]
}

REMOTE_TARGET=""
REMOTE_DEPLOY_PATH=""
ssh_args=()
_resolve_remote() {
  container_load_ci_env
  REMOTE_TARGET="$(container_ssh_target)"
  REMOTE_DEPLOY_PATH="${REMOTE_PATH:-$(container_deploy_path)}"
  [[ -n "${REMOTE_DEPLOY_PATH}" ]] || die "Missing deploy path. Pass --path=DIR or set DEPLOY_PATH." 2
  local arg
  while IFS= read -r arg; do
    ssh_args+=("${arg}")
  done < <(jq -r '.[]' <<< "$(container_ssh_args_json)")
}

_ssh() {
  # shellcheck disable=SC2029 # callers pass commands already quoted locally; they run verbatim remotely
  ssh "${ssh_args[@]}" "${REMOTE_TARGET}" "$@"
}

case "${SUBCOMMAND}" in
  show)
    record="$(revision_build_json "$(revision_source_json)" "${TARGET}" "${MESSAGE}" "" "")"
    if [[ "${JSON}" == "true" ]]; then
      jq '{record: .}' <<< "${record}" | ops_json_envelope "revision"
    else
      ops_section "ops revision show"
      revision_print_record "${record}"
    fi
    ;;

  record)
    source_json="$(revision_source_json)"
    interactive=false
    _can_prompt && interactive=true
    MESSAGE="$(revision_policy_check "${source_json}" "${MESSAGE}" "${ALLOW_DIRTY}" "${interactive}")"
    [[ "${REMOTE}" == "true" ]] && _resolve_remote
    record="$(revision_build_json "${source_json}" "${TARGET}" "${MESSAGE}" "${REMOTE_TARGET}" "${REMOTE_DEPLOY_PATH}")"

    if [[ "${DRY_RUN}" != "true" ]]; then
      revision_append_local "${record}"
      if [[ "${REMOTE}" == "true" ]]; then
        printf '%s\n' "${record}" | _ssh "$(revision_remote_write_command "${REMOTE_DEPLOY_PATH}")" ||
          die "Recorded locally, but writing the record to ${REMOTE_TARGET}:${REMOTE_DEPLOY_PATH} failed." 1
      fi
    fi

    if [[ "${JSON}" == "true" ]]; then
      jq --argjson dry "${DRY_RUN}" --argjson remote "${REMOTE}" --arg local_file "$(revision_local_history_file)" \
        '{record: ., dry_run: $dry, written: {local: (if $dry then null else $local_file end), remote: ($remote and ($dry | not))}}' \
        <<< "${record}" | ops_json_envelope "revision"
    else
      ops_section "ops revision record"
      revision_print_record "${record}"
      if [[ "${DRY_RUN}" == "true" ]]; then
        ops_info "Dry-run only. Nothing was written."
      else
        ops_ok "Recorded in $(revision_local_history_file)${REMOTE_TARGET:+ and on ${REMOTE_TARGET}:${REMOTE_DEPLOY_PATH}}"
      fi
    fi
    ;;

  current)
    _resolve_remote
    deployed="$(_ssh "$(revision_remote_read_command "${REMOTE_DEPLOY_PATH}")")"
    local_json="$(revision_source_json)"
    if [[ -n "${deployed//[[:space:]]/}" ]] && ! jq -e 'type == "object"' >/dev/null 2>&1 <<< "${deployed}"; then
      die "${REMOTE_TARGET}:${REMOTE_DEPLOY_PATH}/${OPS_REVISION_REMOTE_FILE} is not valid JSON." 1
    fi
    [[ -n "${deployed//[[:space:]]/}" ]] || deployed="null"
    # same: the deployed commit is this checkout's HEAD; null when either side has no git.
    comparison="$(jq -n --argjson d "${deployed}" --argjson l "${local_json}" '
      {deployed: $d, local: $l,
       same_commit: (if ($d == null) or ($d.commit == null) or ($l.commit == null) then null else ($d.commit == $l.commit) end)}')"
    if [[ "${JSON}" == "true" ]]; then
      jq --arg remote "${REMOTE_TARGET}" --arg path "${REMOTE_DEPLOY_PATH}" '. + {remote: $remote, deploy_path: $path}' \
        <<< "${comparison}" | ops_json_envelope "revision"
    else
      ops_section "ops revision current (${REMOTE_TARGET}:${REMOTE_DEPLOY_PATH})"
      if [[ "${deployed}" == "null" ]]; then
        ops_warn "No revision recorded on the server yet."
      else
        revision_print_record "${deployed}"
        case "$(jq -r '.same_commit' <<< "${comparison}")" in
          true) ops_ok "This checkout is at the deployed commit." ;;
          false) ops_warn "This checkout is at $(jq -r '.short' <<< "${local_json}"); the server runs $(jq -r '.short' <<< "${deployed}")." ;;
          *) ops_info "No commit to compare (no git on one side)." ;;
        esac
      fi
    fi
    ;;

  history)
    if [[ "${REMOTE}" == "true" ]]; then
      _resolve_remote
      jsonl="$(_ssh "$(revision_remote_history_command "${REMOTE_DEPLOY_PATH}" "${LIMIT}")")"
      where="${REMOTE_TARGET}:${REMOTE_DEPLOY_PATH}/${OPS_REVISION_REMOTE_HISTORY}"
    else
      file="$(revision_local_history_file)"
      jsonl=""
      if [[ -f "${file}" ]]; then
        jsonl="$(tail -n "${LIMIT}" "${file}")"
      fi
      where="${file}"
    fi
    if [[ "${JSON}" == "true" ]]; then
      jq -s --arg where "${where}" '{source: $where, deploys: reverse}' <<< "${jsonl}" | ops_json_envelope "revision"
    else
      ops_section "ops revision history (${where})"
      revision_print_history "${jsonl}"
    fi
    ;;
esac
