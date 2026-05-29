# run command

## Purpose

Execute a single action for one service (`start`, `stop`, `logs`, `build`, `test`, …).

## CLI / entrypoints

```bash
ops run <action> <service_id> [--mode foreground|background]
ops run start backend --foreground
```

## Source files

- `core/commands/run.sh`
- `core/lib/run_plan.sh`, `env.sh`, `preflight.sh`

## Behavior

1. Validates service exists in manifest/config.
2. Generates run plan JSON and writes to `.ops.project/generated/run-plans/`.
3. Runs preflight checks.
4. Dispatches by `selected_strategy` (stack, override, legacy bridge).

## Exit codes

| Code | Meaning |
| --- | --- |
| 2 | Config error |
| 3 | Preflight error |
| 4 | Dependency error |
| 5 | Command failure |

## Testing

```bash
./ops.sh show start <service_id>
./ops.sh run start <service_id> --mode foreground
```

## See also

- [../reference/action-resolution.md](../reference/action-resolution.md)
- [show.md](show.md)
