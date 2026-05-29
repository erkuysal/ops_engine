# logs command

## Purpose

Tail service logs from `.ops.project/logs/` (single service or `--all`).

## CLI / entrypoints

```bash
ops logs <service_id>
ops logs <service_id> --follow
ops logs --all
```

## Source files

- `core/commands/logs.sh`

## Inputs and outputs

**Reads:** `.ops.project/logs/<service_id>.log` or per-process logs for process groups.

## Testing

```bash
./ops.sh logs <service_id>
./ops.sh logs <service_id> --follow
```

## See also

- [start.md](start.md)
