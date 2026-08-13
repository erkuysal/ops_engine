# JSON output standardization

## Goal

Every `ops <command> --json` output should be additive-compatible with the
shared envelope contract (`ok`, `command` at the top level — see
[docs/reference/json-output.md](../docs/reference/json-output.md) and
[schemas/command-result.schema.json](../schemas/command-result.schema.json)),
and every command that has a meaningful read-only or structured answer
should eventually offer `--json` at all. This gives a caller — human or
agent — one place to check success/failure and one place to learn the
`--json` contract, instead of a different shape (or no `--json` at all) per
command.

## Principles

- The envelope is additive: merge `ok`/`command` into a command's existing
  JSON shape via `ops_json_envelope` (`core/lib/output.sh`); do not nest
  existing fields under a new `data` key. Existing consumers that read a
  known field directly must keep working unchanged.
- `ok` means "this command produced valid structured output," not "the
  underlying state is healthy" — those are different questions and some
  commands (e.g. `monitor status`) already have their own nested field for
  the latter. `validate` is the deliberate exception: its `ok` mirrors
  actual pass/fail, matching its exit code, because that's what a
  validator's caller wants first.
- Prefer exposing structured data a command already computes internally
  (e.g. `show` already built the full run-plan object before this work;
  `--json` just prints it) over inventing a new shape from scratch.
- A command that dies before reaching its JSON-construction step still
  exits non-zero with a plain-text `[ERROR]` line, not JSON. Making error
  paths JSON-aware is out of scope for this issue — it would touch `die`
  and the shared logger used by every command, not just the ones listed
  here, and deserves its own issue if pursued.

## Done

- `core/lib/output.sh` (`ops_json_envelope`) and
  `schemas/command-result.schema.json`.
- Retrofitted onto existing `--json` commands: `build`, `deploy`,
  `describe`, `global`, `monitor` (all subcommands: `credentials`, `hosts`,
  `postgres info/databases/users`, `setup`, `status`/`test`), `package`,
  `setup` (`check`, `--module run-plans`), `setup shipping`, `ship`,
  `status`.
- Added `--json` where none existed: `doctor`, `show`, `validate`.
- `tests/smoke/capabilities.bash` (envelope on `describe`), `show.bash`
  (new suite), plus `--json` assertions added to `doctor.bash` and
  `validate.bash`. Existing `--json` assertions in `container-pipeline.bash`,
  `monitor.bash`, `status.bash`, `shipping.bash`, `setup-shipping.bash`, and
  `global-profiles.bash` continue to pass unchanged (the one exception,
  `global list --json`'s bare array becoming `{profiles: [...]}`, was
  updated at its single call site).
- `tests/schema/run.sh` validates `describe --json` at runtime against the
  envelope schema.

## Remaining Work

Commands with no `--json` yet:

- [ ] `env` (`show`, `doctor` subcommands) — needs new
  `env_show_context_json`/`env_doctor_check_json` in `core/lib/env.sh`;
  the existing functions only print human-readable text, unlike `show`
  where a JSON-shaped plan already existed to expose.
- [ ] `backup` (`create`/`list`/`show`/`diff`/`prune`)
- [ ] `ci` (`setup`/`env`/`connect`/`credentials`/`ssh-key`)
- [ ] `cleanup`
- [ ] `init`
- [ ] `install` (and `install doctor`)
- [ ] `logs`
- [ ] `rollback` — dispatches to `backup.sh rollback`; covered once `backup`
  is done
- [ ] `run` — always mutates; decide whether `--json` here should describe
  the resolved plan (duplicating `show`) or just the execution result
- [ ] `stop`
- [ ] `update` — thin wrapper around `setup`; covered once `setup`'s
  remaining subcommands are (this issue only did `check`/`run-plans`)
- [ ] `bootstrap` — thin wrapper around `setup apply-services`

Other follow-ups:

- [ ] Decide whether `ci`/`ssh`/`credentials` (three `main.sh` command
  words dispatching into one script) should share one `--json` contract
  or diverge per subcommand, before implementing `ci`'s `--json`.
- [ ] Consider whether `docs/commands/*.md` for the commands already
  retrofitted (`build`, `deploy`, `global`, `monitor`, `package`, `setup`,
  `ship`, `status`) need their example JSON output updated to show the
  `ok`/`command` fields explicitly, or whether the `docs/reference/json-output.md`
  pointer is sufficient.

## Candidate verification commands

```bash
bash tests/run.sh
bash tests/schema/run.sh
./ops.sh doctor --json
./ops.sh validate --json
./ops.sh show start <service_id> --json
```
