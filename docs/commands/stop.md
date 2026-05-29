# stop command

## Purpose

Stop one or all services, optionally including dependents (`--with-deps`, default).

## CLI / entrypoints

```bash
ops stop <service_id>
ops stop --all
ops stop <service_id> --no-deps
```

## Source files

- `core/commands/stop.sh`
- `core/lib/graph.sh`

## Side effects

Removes or updates PID files; invokes stack stop actions via `run` internally.

## Testing

```bash
./ops.sh stop <service_id>
```

## See also

- [start.md](start.md)
