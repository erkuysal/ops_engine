# status command

## Purpose

Show runtime status for configured services: aggregate state, PIDs, ports,
healthcheck URLs, and config source.

## CLI / entrypoints

```bash
ops status
ops status <service_id>
ops status --json
ops ps                  # alias for status
```

## Source files

- `core/commands/status.sh`
- `core/lib/status.sh`

## Behavior

| State | Meaning |
| --- | --- |
| `running` | All tracked processes are alive |
| `partial` | Some processes alive (typical for process groups) |
| `stopped` | No live processes |

Reads PID files from:

- Single service: `.ops.project/run/<service_id>.pid`
- Process group: `.ops.project/run/<service_id>/<process>.pid`

Docker stack services use `docker compose ps` when `docker` is available,
including `compose_files` from service config when provided.

## Side effects

Read-only. Stale PID files (dead process) are removed when status is checked.

## Testing

```bash
bash tests/run.sh
./ops.sh status --plain
./ops.sh status <service_id> --json
```

## See also

- [start.md](start.md)
- [stop.md](stop.md)
- [show.md](show.md)
