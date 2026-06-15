# doctor command

## Purpose

Read-only health check of orchestrator prerequisites and project ops layout.

## CLI / entrypoints

```bash
ops doctor
ops doctor boundaries
```

Related: `ops install doctor`, `ops setup doctor`, `ops ci doctor`.

## Source files

- `core/commands/doctor.sh`

## Checks

- Bash ≥ 4.3
- `yq`, `jq` presence
- `OPS_PROJECT_ROOT` resolution
- `.ops/core/` integrity
- `.ops/` package directory integrity
- `.ops.project/` state directory availability

`ops doctor boundaries` checks package/project separation:

- no generated/runtime directories under `.ops`
- no secret-like files under `.ops`
- no machine-local paths committed in package files
- no project-specific package references outside test fixtures

## Testing

```bash
./ops.sh doctor
./ops.sh doctor boundaries
```

## See also

- [install.md](install.md)
