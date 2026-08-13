# describe command

## Purpose

Give a caller — human or agent — one machine-readable place to discover
every ops command, what it does, and how safe it is to call, instead of
parsing `--help` text or command source.

## CLI / entrypoints

```bash
ops describe
ops describe --json
ops describe <command>
ops describe <command> --json
```

## Source files

- `core/commands/describe.sh`
- `core/capabilities.json` — the manifest itself (package-owned, hand-maintained)
- `schemas/capabilities.schema.json` — its schema contract

## Behavior

Reads `core/capabilities.json` and prints either the full command list or a
single command's entry. Each entry has:

- `id` / `aliases` — what you type
- `summary` — one-line description
- `status` — `live` or `experimental`
- `safety` — one of:
  - `read_only` — never mutates
  - `preview_by_default` — mutates only with an explicit `--apply` (or
    equivalent); safe to run without one
  - `live_by_default` — mutates immediately unless `--dry-run` is passed
  - `always_mutates` — no preview mechanism exists
  - `plan_only` — mutation is not implemented yet, regardless of flags
- `notes` — caveats that don't fit in `summary` (e.g. which subcommands of a
  multi-purpose command actually mutate)
- `script` / `doc` — where to look next

`safety` was derived from each command's actual flag parsing (`--apply`,
`--dry-run`) and, for multi-subcommand commands, from their own usage text —
not guessed from the command name.

## Keeping the manifest honest

`tests/smoke/capabilities.bash` diffs `core/capabilities.json` against the
command/alias words `core/main.sh` actually dispatches, and fails the smoke
suite if they drift apart (an entry added without a dispatch case, or a
dispatch case added without an entry). It also checks that every `script`/
`doc` path in the manifest resolves to a real file, and exercises
`ops describe --json` end to end.

## Testing

```bash
bash tests/run.sh
./ops.sh describe
./ops.sh describe ship --json
```
