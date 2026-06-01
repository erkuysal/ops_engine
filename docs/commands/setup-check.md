# setup check

## Purpose

Read-only drift detection: compare a fresh workspace discovery scan against materialized `.ops.project/config` (or `.ops.yaml` when config JSON is absent).

Use this before `ops setup --apply` to see what would change, or in CI to fail when the repo layout no longer matches committed config.

## CLI

```bash
ops setup check
ops setup check --json
ops setup --check
ops setup --check --json
```

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | No drift between discovery and config |
| `1` | Drift detected (added/removed/changed services or global env files) |

## What is compared

Per service (discovery proposal vs config):

- `stack`, `path`, `role`
- `env_files`
- inferred `port` and start `command`

Project-level:

- `global_env_files` in `project.json` vs discovery root env scan

Informational (does not affect exit code):

- Whether cached `.ops.project/generated/discovery.json` differs from a fresh scan

## JSON output

`--json` prints a single report object with `summary`, `added`, `removed`, `changed`, and `global_env_files`. Exit code still reflects drift.

## Source files

- `core/commands/setup.sh` — `_run_setup_check`
- `core/lib/setup_check.sh` — compare and report helpers

## Testing

```bash
bash tests/run.sh   # includes setup-check smoke suite
ops setup --apply
ops setup check
```

## See also

- [setup.md](setup.md)
- [../core/discovery.md](../core/discovery.md)
