# Setup module: all and wizard

## Purpose

Runs the full setup path (`all` / default `generate`) or an interactive wizard that lets the user choose which modules to run.

## CLI / entrypoints

```bash
ops setup                    # wizard when TTY; else preview generate
ops setup all --apply
ops setup --interactive --apply
ops setup interactive --apply
ops setup wizard             # explicit wizard (via interactive subcmd)
ops setup --dry-run
```

## Source files

- `core/commands/setup.sh` — `_run_setup_wizard`, `_apply_generated`, `SUBCMD=generate` path
- Module runners: `_run_project_setup`, `_run_apply_services`, `_run_dependencies`, `_run_ci_setup_module`

## Behavior

### Wizard (`_run_setup_wizard`)

When stdin is a TTY and no explicit subcommand/flags target a single module, bare `ops setup` opens the wizard:

1. Prompt: project base
2. Prompt: services/discovery apply
3. Prompt: dependencies
4. Prompt: CI metadata
5. Prompt: apply now (unless `--dry-run` or `--apply` already set)

Sets `INTERACTIVE=true` for nested modules.

### All / generate

`ops setup all` or default `generate` runs the full discovery → config → services → dependencies pipeline (see `_apply_generated` in `setup.sh`).

Non-interactive shells without explicit targets preview instead of hanging on prompts.

## Flags

| Flag | Effect |
| --- | --- |
| `--dry-run` | Preview only; wizard does not apply |
| `--apply` | Write project state |
| `--interactive` | Enable prompts in nested modules |
| `--profile=NAME` | Profile for setup/CI (default from config) |

## Testing

```bash
./ops.sh setup --dry-run
./ops.sh setup all --apply
# Interactive (TTY):
./ops.sh setup
```

## See also

- [project.md](project.md)
- [services.md](services.md)
- [dependencies.md](dependencies.md)
- [ci.md](ci.md)
- [../commands/setup.md](../commands/setup.md)
