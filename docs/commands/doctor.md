# doctor command

## Purpose

Read-only health check of orchestrator prerequisites and project ops layout.

## CLI / entrypoints

```bash
ops doctor
```

Related: `ops install doctor`, `ops setup doctor`, `ops ci doctor`.

## Source files

- `core/commands/doctor.sh`

## Checks

- Bash ≥ 4.3
- `yq`, `jq` presence
- `OPS_PROJECT_ROOT` resolution
- `.ops/core/` integrity
- Writable `.ops/` local dir

## Testing

```bash
./ops.sh doctor
```

## See also

- [install.md](install.md)
