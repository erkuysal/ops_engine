# Adding a setup module

## Purpose

Add a new modular `ops setup <name>` path alongside project, services, dependencies, and ci.

## Steps

1. Add subcommand case in `core/commands/setup.sh` argument parsing (top-level alias and `--module=` case).

2. Implement `_run_<module>_setup` function.

3. Call `_ensure_project_base` when the module writes under `.ops.project/`.

4. Add wizard prompt in `_run_setup_wizard` if it should appear in bare `ops setup`.

5. Document under `docs/setup-modules/<name>.md`.

6. Add row to [CONTRIBUTING.md](../../CONTRIBUTING.md) decision table.

## Flags

Support `--dry-run` (preview) and `--apply` (write) consistently with existing modules.

## Testing

```bash
./ops.sh setup <module>
./ops.sh setup <module> --apply
```

## See also

- [../setup-modules/project.md](../setup-modules/project.md)
