#!/usr/bin/env bash
# Backup and rollback command smoke tests.

suite_backup() {
  local root snapshot_id services_file before_count after_count prune_preview_count
  root="$(fixture_copy config-only)"
  services_file="${root}/.ops.project/config/services.json"

  snapshot_id="$(ops_run "${root}" backup create --label smoke | tail -n 1)"
  assert_file_exists "backup writes manifest" \
    "${root}/.ops.project/.history/config/${snapshot_id}/manifest.json"
  assert_file_exists "backup snapshots services config" \
    "${root}/.ops.project/.history/config/${snapshot_id}/config/services.json"
  assert_ok "backup list exits 0" \
    ops_run "${root}" backup list
  assert_ok "backup show exits 0" \
    ops_run "${root}" backup show "${snapshot_id}"

  jq '.services[0].name = "Changed API"' "${services_file}" > "${services_file}.tmp"
  mv "${services_file}.tmp" "${services_file}"
  assert_jq_eq "fixture config changed before rollback" \
    '.services[0].name' "${services_file}" "Changed API"
  assert_ok "backup diff exits 0" \
    ops_run "${root}" backup diff "${snapshot_id}"

  assert_ok "rollback preview exits 0" \
    ops_run "${root}" rollback "${snapshot_id}"

  before_count="$(find "${root}/.ops.project/.history/config" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  assert_ok "rollback apply exits 0" \
    ops_run "${root}" rollback "${snapshot_id}" --apply
  after_count="$(find "${root}/.ops.project/.history/config" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"

  assert_jq_eq "rollback restores services config" \
    '.services[0].name' "${services_file}" "API"
  assert_eq "rollback creates safety backup" \
    "$((before_count + 1))" "${after_count}"

  before_count="${after_count}"
  assert_ok "setup apply creates pre-setup backup" \
    ops_run "${root}" setup --apply
  after_count="$(find "${root}/.ops.project/.history/config" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  assert_eq "pre-setup backup count increments" \
    "$((before_count + 1))" "${after_count}"

  ops_run "${root}" backup create --label prune-a >/dev/null
  ops_run "${root}" backup create --label prune-b >/dev/null
  before_count="$(find "${root}/.ops.project/.history/config" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  assert_ok "backup prune preview exits 0" \
    ops_run "${root}" backup prune --keep 2
  prune_preview_count="$(find "${root}/.ops.project/.history/config" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  assert_eq "backup prune preview keeps files" "${before_count}" "${prune_preview_count}"
  assert_ok "backup prune apply exits 0" \
    ops_run "${root}" backup prune --keep 2 --apply
  after_count="$(find "${root}/.ops.project/.history/config" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  assert_eq "backup prune keeps requested count" "2" "${after_count}"
}
