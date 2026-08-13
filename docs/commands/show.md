# show command

## Purpose

Read-only inspection of how an action would run (run plan fields, paths, strategy).

## CLI / entrypoints

```bash
ops show <action> <service_id>
ops show start <service_id>
ops show start <service_id> --json
```

## Source files

- `core/commands/show.sh`
- `core/lib/run_plan.sh`

## Side effects

Writes run plan JSON (same as run) but does not execute the service.

## JSON output

`--json` prints the same run-plan object already written to
`.ops.project/generated/run-plans/<service>.<action>.json`, plus a
`run_plan_file` pointer to that file, merged with the shared `ok`/`command`
envelope — see [../reference/json-output.md](../reference/json-output.md).
It exits before any human-readable rendering, so it's cheaper than the
default output as well as more precise.

## Testing

```bash
./ops.sh show start <service_id>
```

## See also

- [run.md](run.md)
- [../core/run-plan.md](../core/run-plan.md)
