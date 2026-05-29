# bootstrap command

## Purpose

Compatibility wrapper routing to `ops setup`.

## CLI / entrypoints

```bash
ops bootstrap [--dry-run] [--force]
```

Maps to:

- `--dry-run` → `ops setup --dry-run`
- otherwise → `ops setup --apply` / `apply-services` paths

## Source files

- `core/commands/bootstrap.sh`

## See also

- [setup.md](setup.md)
- [../reference/legacy.md](../reference/legacy.md)
