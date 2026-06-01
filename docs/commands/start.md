# start command

## Purpose

Dependency-aware service start with optional foreground/background and dry-run ordering preview.

## CLI / entrypoints

```bash
ops start <service_id>
ops start --all
ops start <service_id> --with-deps|--no-deps
ops start <service_id> --foreground|--background
ops start <service_id> --no-wait
ops start <service_id> --dry-run
```

## Source files

- `core/commands/start.sh`
- `core/lib/graph.sh`, `core/lib/healthcheck.sh`, `core/lib/settings.sh`

## Healthcheck wait

After a service starts successfully, `ops start` waits for its HTTP healthcheck when configured:

- Explicit `healthcheck` URL on the service in config
- Otherwise inferred from `setup.port` as `http://localhost:<port>/`

Settings under `settings.start.healthcheck`:

| Field | Default | Meaning |
| --- | --- | --- |
| `wait` | `true` | Wait for healthchecks after start |
| `timeout_seconds` | `60` | Give up after this many seconds |
| `interval_seconds` | `1` | Delay between probe attempts |

Use `--no-wait` to skip health polling. Requires `curl` for HTTP probes.

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
