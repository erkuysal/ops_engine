# Setup module: ci

## Purpose

Delegates to the CI command to configure local deploy/CI metadata and secrets templates—without requiring GitHub Actions.

## CLI / entrypoints

```bash
ops setup ci
ops setup ci --interactive --apply
ops setup ci --global-profile personal-vps --apply
```

## Source files

- `core/commands/setup.sh` — `_run_ci_setup_module`
- `core/commands/ci.sh` — `setup`, `env` subcommands

## Inputs and outputs

**Writes (with `--apply`):**

| Path | Description |
| --- | --- |
| `.ops.project/config/ci.json` | Server/registry metadata (non-secret) |
| `.ops.project/secrets/ci.env` | Local secrets template (via `ops ci env --apply`) |

## Behavior

1. Calls `ops ci setup` with forwarded `--interactive`, `--apply`, `--profile`,
   and `--global-profile`.
2. On apply, also runs `ops ci env --apply` for the secrets template.
3. Preview mode suggests `ops ci env` for the env file.

Interactive mode presents saved/create/project-only/later connection choices.
This is the same flow used lazily by the first interactive deploy when no
complete connection is configured.

## Extension points

Extend `ci.sh` for new credential types; keep secrets out of the package repo.

## Testing

```bash
./ops.sh setup ci
./ops.sh setup ci --interactive --apply
./ops.sh ci doctor
./ops.sh credentials
```

## See also

- [../commands/ci.md](../commands/ci.md)
- [../reference/config-files.md](../reference/config-files.md)
