# show command

## Purpose

Read-only inspection of how an action would run (run plan fields, paths, strategy).

## CLI / entrypoints

```bash
ops show <action> <service_id>
ops show start userengine
```

## Source files

- `core/commands/show.sh`
- `core/lib/run_plan.sh`

## Side effects

Writes run plan JSON (same as run) but does not execute the service.

## Testing

```bash
./ops.sh show start <service_id>
```

## See also

- [run.md](run.md)
- [../core/run-plan.md](../core/run-plan.md)
