# Development workflow

## Purpose

How to change the ops package and verify behavior from a consuming repository.

## Prerequisites

- Bash 4+
- `jq` (required by setup, run-plan, discovery)
- `yq` (YAML compatibility import/export and fallback validation)
- Stack-specific tools when testing those stacks (e.g. `go`, `node`, `python`)

## Repository layout

`.ops` is its own git repository (often embedded in a parent project). Edit files under `.ops/`; run commands from the **parent project root** where `ops.sh` lives:

```bash
cd /path/to/parent-project
./ops.sh setup --dry-run
./ops.sh show start <service_id>
```

Alternatively, after `ops install`, use global `ops` from any directory that contains `.ops/core/main.sh` upward.

## Environment variables

| Variable | Effect |
| --- | --- |
| `OPS_DEBUG=true` | Trace via `debug()` in `core/lib/init.sh` |
| `OPS_PLAIN=true` | No ANSI colors; suitable for CI |
| `OPS_PROJECT_ROOT` | Set by `ops.sh`; project root path |
| `OPS_NON_INTERACTIVE=true` | Disables prompts in start/setup paths |
| `OPS_USE_LEGACY=true` | Parent `ops.sh` routes to legacy scripts |

## Safe change workflow

1. Edit package code under `.ops/core/`.
2. Run package smoke tests: `bash tests/run.sh` (from the `.ops` repo root).
3. Preview mutating commands with `--dry-run` before `--apply`.
4. Run targeted integration smoke checks (below) when changing runtime behavior.
5. Update the matching file under `docs/` for your change.
6. Note significant behavior changes in `ONGOING.md` if applicable.

## Automated tests

From the `.ops` repository root:

```bash
bash tests/run.sh
```

Fixtures under `tests/fixtures/` are minimal fake projects (Go process group, Node
workspace, config-only validate). CI runs the same suite on Ubuntu via
`.github/workflows/ci.yml`.

When adding discovery or setup behavior, extend fixtures and smoke suites under
`tests/smoke/` rather than relying only on a consuming monorepo.

## Smoke checks

```bash
./ops.sh install doctor
./ops.sh setup --dry-run
./ops.sh setup project --dry-run
./ops.sh validate --plain
./ops.sh doctor
./ops.sh show start <service_id>
./ops.sh start <service_id> --dry-run
```

For setup apply paths:

```bash
./ops.sh setup project --apply
./ops.sh setup services --apply
```

Use a throwaway branch or copy of `.ops.project/` when testing destructive apply flows.

## Debugging

- `OPS_DEBUG=true ./ops.sh show start <service_id>` — inspect resolution without running
- Inspect run plan JSON: `.ops.project/generated/run-plans/<service>.<action>.json`
- Inspect discovery: `.ops.project/generated/discovery.json`

## Coding conventions

Match existing style in `core/lib/init.sh`:

- `set -euo pipefail` at top of scripts
- Guard double-sourcing with `_OPS_*_LOADED` variables
- Use `die`, `warn`, `info`, `ok`, `debug` from init or `ops_*` from logger
- Prefer `require_bins` for external dependencies
- Run `shellcheck` on touched scripts when available

## See also

- [../CONTRIBUTING.md](../CONTRIBUTING.md)
- [commands/setup.md](commands/setup.md)
- [reference/config-files.md](reference/config-files.md)
