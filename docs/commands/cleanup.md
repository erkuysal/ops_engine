# cleanup command

## Purpose

Preview or remove generated runtime state under `.ops.project`.

## CLI / entrypoints

```bash
ops cleanup
ops cleanup --pids --apply
ops cleanup --logs-older-than=30
ops cleanup --logs-older-than=30 --apply
```

## Source files

- `core/commands/cleanup.sh`
- `core/lib/cleanup.sh`

## Behavior

Without flags, `ops cleanup` previews stale PID files under `.ops.project/run`.
It does not remove anything unless `--apply` is passed.

Log cleanup is opt-in and age-based:

```bash
ops cleanup --logs-older-than=30 --apply
```

## Testing

```bash
bash tests/run.sh
./ops.sh cleanup
```
