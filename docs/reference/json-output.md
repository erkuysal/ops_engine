# JSON output (`--json`)

## Purpose

Give a caller — human or agent — a consistent way to tell whether an
`ops <command> --json` invocation succeeded and which command produced it,
without having to learn a different top-level shape per command.

## The envelope

Every command's `--json` output is a JSON object that includes, at minimum:

```json
{
  "ok": true,
  "command": "build"
}
```

alongside whatever fields that command already returns, at the same top
level — not nested under a `data` key. This is additive by design: a
consumer reading a known field directly (e.g. `package --json | jq .git.branch`)
keeps working after this contract was added; it doesn't need to reach into
a wrapper first.

The contract is `schemas/command-result.schema.json`. It requires only `ok`
(boolean) and `command` (non-empty string); everything else is
command-specific and unconstrained by this schema (each command's own
fields are documented on its own page under `docs/commands/`).

`ok` means "this command produced valid structured output," not
necessarily "everything it reports is healthy" — a command can report
`ok: true` with an unhealthy result inside (e.g. `monitor status --json`'s
`summary.ok` reflects target health, which is a separate, nested field).
**`validate` is the one deliberate exception**: its top-level `ok` mirrors
whether validation actually passed (`errors == 0`), because that is the
one thing callers of a validator want to check first, and it already
matches the command's exit code.

## What `ok` does not cover

A command that dies before reaching its JSON-construction step still exits
non-zero with a plain-text `[ERROR] ...` line on stderr, not JSON. Error
paths are not JSON-formatted yet — treat a non-zero exit with no JSON on
stdout as failure, the same way you would today.

## Implementation

`core/lib/output.sh` provides `ops_json_envelope COMMAND [OK]`, which reads
an already-built JSON object on stdin and merges `{ok: OK, command: COMMAND}`
into it (`OK` defaults to `true`). Every command below pipes its existing
`jq` construction through this instead of building the envelope by hand.

## Commands with `--json` today

| Command | Notes |
| --- | --- |
| `build` | |
| `deploy` | |
| `describe` | Lists under `commands: [...]` |
| `doctor` | Not supported for `doctor boundaries` |
| `global` | `list`/`current` return their own shape; see [global.md](../commands/global.md) |
| `monitor` | Several subcommands (`credentials`, `hosts`, `postgres info/databases/users`, `setup`, `status`/`test`) each carry their own `command` value, e.g. `"monitor postgres info"` |
| `package` | |
| `setup` | `setup check` and `setup --module run-plans` |
| `setup shipping` | `command` is `"setup shipping"` |
| `ship` | Always plan-only regardless of flags — see [ship.md](../commands/ship.md) |
| `show` | Exposes the same run-plan object already written to `.ops.project/generated/run-plans/` |
| `status` | |
| `validate` | See the `ok` exception above |

Commands without `--json` yet (`backup`, `ci`, `cleanup`, `env`, `init`,
`install`, `logs`, `rollback`, `run`, `stop`, `update`, `bootstrap`) are
tracked in [`ISSUES/3_JSON_OUTPUT_STANDARDIZATION.md`](../../ISSUES/3_JSON_OUTPUT_STANDARDIZATION.md).

## Testing

```bash
bash tests/schema/run.sh   # schema contract + a runtime describe --json check
bash tests/run.sh          # tests/smoke/capabilities.bash, show.bash, doctor.bash,
                            # validate.bash, plus per-command --json assertions
                            # in container-pipeline.bash, monitor.bash, status.bash,
                            # shipping.bash, setup-shipping.bash, global-profiles.bash
```
