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
- `core/lib/run_plan.sh`, `command_exec.sh`, `env.sh`, `preflight.sh`

## Behavior

1. Validates service exists in project config or YAML fallback.
2. Generates run plan JSON and writes to `.ops.project/generated/run-plans/`.
3. Runs preflight checks.
4. Dispatches by `selected_strategy` (stack, override, legacy bridge).

Configured action strings intentionally support Bash syntax such as pipelines,
redirects, and substitutions. They are transported with shell-safe quoting and
executed exactly once by a child Bash process. They do not run through `eval`
inside the orchestrator shell.

Configured actions are trusted project code, not a security sandbox. Only run
configuration reviewed with the repository.

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
bash tests/run.sh  # includes quote/substitution/multiline transport coverage
```

## See also

- [../reference/action-resolution.md](../reference/action-resolution.md)
- [show.md](show.md)
