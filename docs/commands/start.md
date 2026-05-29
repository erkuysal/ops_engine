# start command

## Purpose

Dependency-aware service start with optional foreground/background and dry-run ordering preview.

## CLI / entrypoints

```bash
ops start <service_id>
ops start --all
ops start <service_id> --with-deps|--no-deps
ops start <service_id> --foreground|--background
ops start <service_id> --dry-run
```

## Source files

- `core/commands/start.sh`
- `core/lib/graph.sh`, `settings.sh`

## Side effects

**Writes:** logs under `.ops.project/logs/`, PIDs under `.ops.project/run/`

Delegates execution to `run.sh` per service.

## Testing

```bash
./ops.sh start <service_id> --dry-run
./ops.sh start <service_id> --background
```

## See also

- [stop.md](stop.md)
- [run.md](run.md)
