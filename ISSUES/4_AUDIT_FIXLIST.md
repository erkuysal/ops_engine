# Audit fix list

Findings from a codebase audit on 2026-08-25. Fix one at a time, in order —
each item is scoped to be a single small commit.

## Principles

- Fix in priority order (top of list = do first). Priority is blast radius ×
  cheapness to fix, not codebase area.
- Each item should land as its own commit/PR so the checklist stays an
  accurate log of what's actually done.
- Do not batch unrelated items into one commit even if they touch the same
  file.

## Checklist

- [x] **1. Secret files written world-readable before `chmod 600`.** Three
  call sites create a file, write plaintext secrets/env values into it, and
  only `chmod 600` afterward — a window where the file is at the process
  umask (typically `644`) and readable by other local users on a shared
  machine. Fix: `umask 077` before creating the file (or create with
  `install -m 600 /dev/null "$out"` first, then write), applied consistently
  at all three sites.
  - `core/lib/env_materialize.sh:100-114` (`env_materialize_generated`)
  - `core/commands/monitor.sh:238-247` (`_write_monitor_env_template`)
  - `core/commands/ci.sh:800-806` (`_ci_env_init`)

- [x] **2. Shellcheck CI gate doesn't catch quoting/word-splitting bugs.**
  `.github/workflows/ci.yml:75` ran `shellcheck --severity=error -e
  SC1091,SC2034,SC2154`. SC2086 (unquoted expansion) is `info`-tier, not
  `warning`-tier as originally assumed here — `--severity=warning` alone
  does not catch it; `--severity=info` does. Tightened to
  `--severity=info` (same `-e` exclusions), fixed all 86 findings that
  surfaced (mechanical `${VAR#${OTHER}/}` quoting via shellcheck's own
  `--format=diff`, three real `A && B || C` bugs where a failed `printf`
  could fall through to a duplicate/wrong fallback, two unquoted
  cross-shell command-prefix arrays rewritten as bash arrays instead of
  silenced, one `ls | sort` replaced with a `nullglob` array, and several
  justified inline `shellcheck disable` comments for intentional literal
  `$var` display text / PowerShell / jq syntax / trap-invoked functions),
  and confirmed CI now fails on a deliberately unquoted expansion.

- [ ] **3. No smoke coverage for `start`, `stop`, `install`.** These mutate
  real state (background processes + PID files, global launcher install)
  with zero automated coverage. Add `tests/smoke/start.bash`,
  `tests/smoke/stop.bash`, `tests/smoke/install.bash` following the existing
  suite structure in `tests/lib/harness.sh`.

- [ ] **4. No smoke coverage for `deploy`, `logs`, `ci`.** Same gap, lower
  urgency than #3 since these have smaller/less destructive blast radius.
  Add `tests/smoke/deploy.bash`, `tests/smoke/logs.bash`,
  `tests/smoke/ci.bash`.

- [ ] **5. `ops ship` has no execution path.** `core/commands/ship.sh:158`
  unconditionally dies on any non-dry-run invocation. This is the larger
  feature-completeness gap already tracked as open work in `ONGOING.md`
  ("implement safe shipping execution with receipts, resume, verification,
  and rollback") — listed here so it stays on the same one-at-a-time
  checklist. Scope as its own multi-step slice when picked up; don't try to
  land it as one commit.

- [ ] **6. No automated guard against legacy-YAML-write regressions.**
  `core/lib/boundaries.sh` already does static text scanning for
  package-boundary violations (`boundary_scan_text`). Extend the same
  mechanism to fail on new `yq e -i` writes to `${OPS_MANIFEST}` or
  `require_manifest` calls outside the explicit
  export/import/validation/migration files whitelisted in
  `ISSUES/2_OPS_YAML_RETIREMENT.md` Slice 7/8. Currently this is enforced by
  contributor discipline and docs only.

- [ ] **7. `--json` missing on state-mutating commands.** Already tracked in
  `ISSUES/3_JSON_OUTPUT_STANDARDIZATION.md`; re-listed here only to flag
  priority order within that issue — `run`, `stop`, and `install` are the
  commands most worth doing first if `ops` is meant to be script/agent-driven,
  since those are the ones a caller most needs a structured success/failure
  signal from.

## Not on this list

- Cross-platform (WSL/Windows) test coverage — already tracked in
  `ISSUES/1_CROSS_PLATFORM.md` and structurally blocked on having a
  Windows/WSL CI runner, not a small fix.
- `.ops.project/config` vs `.ops.yaml` migration — already tracked in
  `ISSUES/2_OPS_YAML_RETIREMENT.md` and mostly complete per that checklist.
