#!/usr/bin/env bash
# Deploy revision records: git and no-git sources, the dirty-tree policy, local and
# server history, and the record ops deploy writes after a successful deploy.

# Usage: _revision_remote ROOT ARGS... — ops_run against a fake server in REVISION_SERVER.
_revision_remote() {
  local root="$1"
  shift
  PATH="${OPS_TESTS_DIR}/fixtures/bin:${PATH}" FAKE_SSH_LOG="${REVISION_SERVER}.ssh.log" \
    DEPLOY_PATH="${REVISION_SERVER}/app" ops_run "${root}" "$@"
}

_revision_git_commit() {
  git -C "$1" -c user.email=test@example.test -c user.name=test commit -q --allow-empty -m "$2"
}

suite_revision() {
  local root json server fake_log history

  # ── No git: time-based id, the message is the description ─────────────────
  root="$(fixture_copy container-pipeline)"
  history="${root}/.ops.project/.history/deploys.jsonl"

  json="$(ops_run "${root}" revision show --json)"
  assert_eq "revision show without git reports source none" "none" "$(jq -r '.record.source' <<< "${json}")"
  assert_eq "revision id without git ends in nogit" "true" "$(jq -r '.record.id | endswith("-nogit")' <<< "${json}")"

  json="$(ops_run "${root}" revision record --target=staging -m "manual release" --json)"
  assert_eq "revision record keeps the message" "manual release" "$(jq -r '.record.message' <<< "${json}")"
  assert_eq "revision record keeps the target" "staging" "$(jq -r '.record.target' <<< "${json}")"
  assert_file_exists "revision record writes the local history" "${history}"

  assert_ok "revision record without git or message still records (by time)" \
    ops_run "${root}" revision record
  assert_eq "local history has one line per record" "2" "$(wc -l < "${history}" | tr -d ' ')"

  printf '{"settings":{"revision":{"require_message":true}}}\n' > "${root}/.ops.project/config/settings.json"
  assert_fail "require_message refuses a record without --message" 2 \
    ops_run "${root}" revision record

  # ── Git: commit, branch, dirty policy ─────────────────────────────────────
  root="$(fixture_copy container-pipeline)"
  git -C "${root}" init -q -b main
  git -C "${root}" add -A
  _revision_git_commit "${root}" "first release"

  json="$(ops_run "${root}" revision show --json)"
  assert_eq "revision show in git reports source git" "git" "$(jq -r '.record.source' <<< "${json}")"
  assert_eq "revision show reports the commit" "$(git -C "${root}" rev-parse HEAD)" "$(jq -r '.record.commit' <<< "${json}")"
  assert_eq "revision show reports the subject" "first release" "$(jq -r '.record.subject' <<< "${json}")"
  assert_eq "revision show reports a clean tree" "false" "$(jq -r '.record.dirty' <<< "${json}")"

  assert_ok "revision record in a clean tree needs no message" \
    ops_run "${root}" revision record
  assert_eq "ops state does not make the tree dirty" "false" \
    "$(ops_run "${root}" revision show --json | jq -r '.record.dirty')"

  printf 'change\n' > "${root}/uncommitted.txt"
  assert_fail "revision record refuses uncommitted changes" 2 \
    ops_run "${root}" revision record
  json="$(ops_run "${root}" revision record --allow-dirty --json)"
  assert_eq "--allow-dirty records the tree as dirty" "true,1" "$(jq -r '[.record.dirty, .record.changed_files] | join(",")' <<< "${json}")"

  json="$(ops_run "${root}" revision record --dry-run --allow-dirty --json)"
  assert_eq "revision record --dry-run writes nothing" "null" "$(jq -r '.written.local' <<< "${json}")"

  json="$(ops_run "${root}" revision history --json)"
  assert_eq "revision history lists newest first" "true,false" \
    "$(jq -r '[.deploys[0].dirty, .deploys[1].dirty] | join(",")' <<< "${json}")"

  # ── Server: record, current, history ──────────────────────────────────────
  server="$(mktemp -d "${TMPDIR:-/tmp}/ops-revision-server-XXXXXX")"
  fake_log="${server}.ssh.log"
  HARNESS_FIXTURES+=("${server}" "${fake_log}")
  REVISION_SERVER="${server}"
  rm -f "${root}/uncommitted.txt"

  _revision_remote "${root}" revision record --remote --target=staging >/dev/null
  assert_file_exists "revision record --remote writes the current revision" "${server}/app/.ops-revision.json"
  assert_eq "server history gets the record" "staging" "$(jq -r '.target' "${server}/app/.ops-deploys.jsonl")"

  json="$(_revision_remote "${root}" revision current --json)"
  assert_eq "revision current matches this checkout" "true" "$(jq -r '.same_commit' <<< "${json}")"

  _revision_git_commit "${root}" "second release"
  json="$(_revision_remote "${root}" revision current --json)"
  assert_eq "revision current notices a newer checkout" "false" "$(jq -r '.same_commit' <<< "${json}")"

  # ── ops deploy records after success, and tells compose the revision ──────
  _revision_remote "${root}" deploy --service=infra --target=staging >/dev/null
  assert_eq "ops deploy passes OPS_REVISION_COMMIT to compose" "true" \
    "$(grep -q "OPS_REVISION_COMMIT=$(git -C "${root}" rev-parse HEAD)" "${fake_log}" && echo true || echo false)"
  assert_eq "ops deploy writes the server record" "second release" "$(jq -r '.subject' "${server}/app/.ops-revision.json")"
  assert_eq "server history keeps every deploy" "2" "$(wc -l < "${server}/app/.ops-deploys.jsonl" | tr -d ' ')"

  json="$(_revision_remote "${root}" revision history --remote --json)"
  assert_eq "revision history --remote reads the server history" "second release" "$(jq -r '.deploys[0].subject' <<< "${json}")"

  printf 'change\n' > "${root}/uncommitted.txt"
  assert_fail "ops deploy refuses uncommitted changes" 2 \
    _revision_remote "${root}" deploy --service=infra
  assert_ok "ops deploy --no-record skips the policy" \
    _revision_remote "${root}" deploy --service=infra --no-record
  assert_eq "--no-record leaves the server history alone" "2" "$(wc -l < "${server}/app/.ops-deploys.jsonl" | tr -d ' ')"

  json="$(ops_run "${root}" deploy --service=infra --dry-run --json)"
  assert_eq "deploy --json shows the revision it would record" "true" "$(jq -r '.revision.dirty' <<< "${json}")"
}
