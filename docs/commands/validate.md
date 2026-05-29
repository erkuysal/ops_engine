# validate command

## Purpose

Multi-pass validation of project ops config. Accepts `.ops.yaml` or `.ops.project/config/services.json` (config-only projects use a temporary manifest for validation).

## CLI / entrypoints

```bash
ops validate [--plain]
```

When only config exists, validation reads `.ops.project/config` via `manifest_prepare_validation_source` in `core/lib/manifest.sh` / `manifest_sync.sh`.

## Source files

- `core/commands/validate.sh`
- `core/lib/manifest.sh`, `graph.sh`, `setup.sh`

## Passes

1. Syntax — `yq` parses `.ops.yaml`
2. Structural — required keys and types
3. Semantic — duplicate IDs, unknown stacks, `depends_on` refs, env policies
4. Filesystem — service paths and env files exist

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Passed (warnings OK) |
| 1 | Errors found |
| 2 | Missing config/manifest or `yq` |

## Config-only projects

If `.ops.yaml` is absent but `.ops.project/config/services.json` exists, validate builds a temporary manifest from config and runs the same passes.

## Testing

```bash
./ops.sh validate --plain
```

## See also

- [../core/manifest.md](../core/manifest.md)
