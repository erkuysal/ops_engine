#!/usr/bin/env bash
# .ops/core/lib/revision.sh - Deploy revision records and deployment history.
#
# A revision record says what was deployed, when, by whom, and where:
#
#   {"id": "20261024T130000Z-1a2b3c4", "source": "git", "commit": "...", "dirty": false, ...}
#
# Git is optional. In a git work tree the record carries the commit, branch, subject and
# a dirty flag; elsewhere ("source": "none") the id is time-based and the operator's
# message is the only description, so ops asks for one.
#
# History is append-only JSON Lines:
#   local   .ops.project/.history/deploys.jsonl   (every recorded deploy from this machine)
#   remote  DEPLOY_PATH/.ops-deploys.jsonl         (every deploy to that path, from anywhere)
#   remote  DEPLOY_PATH/.ops-revision.json         (the current deploy)
#
# Settings (.ops.project/config/settings.json, under "settings.revision"):
#   enabled          (default true)  record revisions during ops deploy
#   allow_dirty      (default false) deploy uncommitted git changes without --allow-dirty
#   require_message  (default false) require --message even in a git work tree
#
# Requires: init.sh, settings.sh and jq.

set -euo pipefail
if [[ "${_OPS_CORE_REVISION_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_REVISION_LOADED=1

# shellcheck source=settings.sh
source "${OPS_CORE_ROOT}/lib/settings.sh"

OPS_REVISION_REMOTE_FILE=".ops-revision.json"
OPS_REVISION_REMOTE_HISTORY=".ops-deploys.jsonl"

revision_local_history_file() {
  printf '%s/deploys.jsonl' "${OPS_PROJECT_HISTORY_DIR}"
}

revision_has_git() {
  command -v git >/dev/null 2>&1 &&
    git -C "${OPS_PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
    git -C "${OPS_PROJECT_ROOT}" rev-parse --verify HEAD >/dev/null 2>&1
}

# Usage: revision_source_json
# Prints {source, commit, short, branch, subject, dirty, changed_files} for the project.
revision_source_json() {
  if ! revision_has_git; then
    jq -n '{source: "none", commit: null, short: null, branch: null, subject: null, dirty: null, changed_files: null}'
    return 0
  fi
  local commit short branch subject changed
  commit="$(git -C "${OPS_PROJECT_ROOT}" rev-parse HEAD)"
  short="$(git -C "${OPS_PROJECT_ROOT}" rev-parse --short HEAD)"
  branch="$(git -C "${OPS_PROJECT_ROOT}" symbolic-ref --quiet --short HEAD 2>/dev/null || printf '')"
  subject="$(git -C "${OPS_PROJECT_ROOT}" log -1 --format=%s)"
  # Untracked files count too: sync-based deploys copy them. ops' own state (this history
  # included) is not part of what gets deployed.
  changed="$(git -C "${OPS_PROJECT_ROOT}" status --porcelain --untracked-files=normal -- . ':(exclude).ops.project' |
    wc -l | tr -d '[:space:]')"
  jq -n \
    --arg commit "${commit}" --arg short "${short}" --arg branch "${branch}" --arg subject "${subject}" \
    --argjson changed "${changed}" \
    '{source: "git", commit: $commit, short: $short, branch: (if $branch == "" then null else $branch end),
      subject: $subject, dirty: ($changed > 0), changed_files: $changed}'
}

# Usage: revision_build_json SOURCE_JSON TARGET MESSAGE REMOTE DEPLOY_PATH
# Prints the complete record. TARGET, MESSAGE, REMOTE and DEPLOY_PATH may be empty.
revision_build_json() {
  local source_json="$1" target="$2" message="$3" remote="$4" path="$5"
  local now stamp by project
  now="$(ops_timestamp)"
  stamp="$(printf '%s' "${now}" | tr -d ':-')"
  by="$(id -un 2>/dev/null || printf 'unknown')@$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown')"
  project="$(jq -r '.name // empty' "${OPS_PROJECT_CONFIG_DIR}/project.json" 2>/dev/null || true)"
  [[ -n "${project}" ]] || project="$(basename "${OPS_PROJECT_ROOT}")"
  jq -c -n \
    --argjson src "${source_json}" \
    --arg stamp "${stamp}" --arg now "${now}" --arg by "${by}" --arg project "${project}" \
    --arg target "${target}" --arg message "${message}" --arg remote "${remote}" --arg path "${path}" \
    --arg ops_version "${OPS_CORE_VERSION:-}" \
    'def nullable: if . == "" then null else . end;
     {id: ($stamp + "-" + ($src.short // "nogit")),
      project: $project, target: ($target | nullable),
      deployed_at: $now, deployed_by: $by,
      remote: ($remote | nullable), deploy_path: ($path | nullable),
      message: ($message | nullable),
      ops_version: ($ops_version | nullable)} + $src'
}

# Usage: revision_policy_check SOURCE_JSON MESSAGE ALLOW_DIRTY INTERACTIVE
# Prints the message to record (possibly prompted for). Dies when the policy refuses.
revision_policy_check() {
  local source_json="$1" message="$2" allow_dirty="$3" interactive="$4"
  local source dirty require_message
  source="$(jq -r '.source' <<< "${source_json}")"
  dirty="$(jq -r '.dirty' <<< "${source_json}")"
  require_message="$(ops_setting_bool '.revision.require_message' 'false')"
  [[ "${allow_dirty}" == "true" ]] || allow_dirty="$(ops_setting_bool '.revision.allow_dirty' 'false')"

  if [[ "${source}" == "git" && "${dirty}" == "true" && "${allow_dirty}" != "true" ]]; then
    die "The work tree has $(jq -r '.changed_files' <<< "${source_json}") uncommitted change(s), so commit $(jq -r '.short' <<< "${source_json}") would not describe this deploy.
Commit first, or pass --allow-dirty (recorded as dirty)." 2
  fi

  # Without git the message is the only description; ask for one rather than record nothing.
  if [[ -z "${message}" && ( "${source}" == "none" || "${require_message}" == "true" ) ]]; then
    if [[ "${interactive}" == "true" ]]; then
      printf 'Deploy message (what is being deployed): ' >&2
      IFS= read -r message || true
    fi
    if [[ -z "${message}" && "${require_message}" == "true" ]]; then
      die "A deploy message is required. Pass --message=TEXT." 2
    fi
    if [[ -z "${message}" && "${source}" == "none" ]]; then
      warn "No git work tree and no --message: this deploy is recorded by time only."
    fi
  fi
  printf '%s' "${message}"
}

# Usage: revision_append_local RECORD_JSON
revision_append_local() {
  local file
  file="$(revision_local_history_file)"
  ensure_dir "$(dirname "${file}")"
  printf '%s\n' "$(jq -c '.' <<< "$1")" >> "${file}"
}

# Usage: revision_remote_write_command DEPLOY_PATH
# The remote shell command that reads one record on stdin, appends it to the history and
# replaces the current-revision file atomically.
revision_remote_write_command() {
  local path q
  path="$1"
  q="$(printf '%q' "${path}")"
  # shellcheck disable=SC2016 # $tmp and $(mktemp) are meant to expand on the server
  printf 'mkdir -p %s && cd %s && tmp=$(mktemp %s.XXXXXX) && cat > "$tmp" && cat "$tmp" >> %s && chmod 644 "$tmp" && mv "$tmp" %s' \
    "${q}" "${q}" "${OPS_REVISION_REMOTE_FILE}" "${OPS_REVISION_REMOTE_HISTORY}" "${OPS_REVISION_REMOTE_FILE}"
}

revision_remote_read_command() {
  printf 'cat %s/%s 2>/dev/null || true' "$(printf '%q' "$1")" "${OPS_REVISION_REMOTE_FILE}"
}

# Usage: revision_remote_history_command DEPLOY_PATH LIMIT
revision_remote_history_command() {
  printf 'tail -n %s %s/%s 2>/dev/null || true' "$2" "$(printf '%q' "$1")" "${OPS_REVISION_REMOTE_HISTORY}"
}

# Usage: revision_print_record RECORD_JSON
revision_print_record() {
  jq -r '
    "  id:          \(.id)",
    "  source:      \(if .source == "git" then "git \(.short)\(if .dirty then " + \(.changed_files) uncommitted change(s)" else "" end) on \(.branch // "detached HEAD")" else "none (no git work tree)" end)",
    (if .subject then "  commit:      \(.subject)" else empty end),
    (if .message then "  message:     \(.message)" else empty end),
    (if .target then "  target:      \(.target)" else empty end),
    (if .remote then "  remote:      \(.remote):\(.deploy_path // "")" else empty end),
    "  deployed:    \(.deployed_at) by \(.deployed_by)"' <<< "$1"
}

# Usage: revision_print_history JSONL
revision_print_history() {
  local jsonl="$1"
  if [[ -z "${jsonl//[[:space:]]/}" ]]; then
    printf '  (no recorded deploys)\n'
    return 0
  fi
  jq -r -s 'reverse | .[] |
    "  \(.deployed_at)  \(.target // "-")  \(if .source == "git" then .short + (if .dirty then "+dirty" else "" end) else "no-git" end)  \(.message // .subject // "")"' <<< "${jsonl}"
}
