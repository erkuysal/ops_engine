# Setup module: project

## Purpose

Creates the base `.ops.project` directory tree and minimum config files. Other setup modules call `_ensure_project_base` when applying changes.

## CLI / entrypoints

```bash
ops setup project
ops setup project --apply
ops setup --module=project --apply
```

## Source files

- `core/commands/setup.sh` — `_run_project_setup`, `_ensure_project_base`, `_project_base_json`, `_write_project_gitignore`

## Inputs and outputs

**Reads:** existing `.ops.project/config/project.json` (skips rewrite if present).

**Writes (with `--apply`):**

| Path | Description |
| --- | --- |
| `.ops.project/` | State root |
| `.ops.project/config/project.json` | Base project metadata |
| `.ops.project/.gitignore` | Ignores logs, run state, secrets |
| `.ops.project/config/`, `generated/`, `logs/`, `run/`, `profiles/` | Directories created |
| `ops.sh` | Project-local launcher, created only when missing |

## Behavior

Without `--apply`, prints planned paths and exits. With `--apply`, creates directories, `project.json`, and the missing project launcher.

Idempotent: re-running does not overwrite existing `project.json` or `ops.sh`.

## Extension points

Add new default config files in `_ensure_project_base` or `_project_base_json`; document shapes in [reference/config-files.md](../reference/config-files.md).

## Testing

```bash
./ops.sh setup project
./ops.sh setup project --apply
```

## See also

- [services.md](services.md)
- [all-and-wizard.md](all-and-wizard.md)
- [../reference/config-files.md](../reference/config-files.md)
