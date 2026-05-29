# init command

## Purpose

Interactive manifest wizard (legacy Phase 2 path). Prefer `ops setup` for new projects.

## CLI / entrypoints

```bash
ops setup init [--profile NAME] [--apply]
ops init
```

## Source files

- `core/commands/init.sh`
- `core/commands/setup.sh` (`init` subcmd sets interactive generate)

## See also

- [setup.md](setup.md)
- [bootstrap.md](bootstrap.md)
