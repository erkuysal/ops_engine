# Config files reference

## Purpose

Layout of `.ops.project` — project memory and generated runtime state.

## Directory tree

```text
.ops.project/
  .gitignore
  .history/              # backups from setup apply
  config/
    project.json
    services.json
    settings.json
    profiles.json
    decisions.json
    ci.json
  generated/
    discovery.json
    setup.json
    project_structure.json
    project_values.json
    run-plans/
      <service>.<action>.json
    bin/                   # e.g. Go process_group builds
  logs/
  profiles/
  run/                     # PID files
  secrets/
    ci.env                 # local only, gitignored
```

## File roles

| File | Written by | Consumed by |
| --- | --- | --- |
| `config/project.json` | setup project / materialize | setup lib, runtime |
| `config/services.json` | setup services | manifest lib, run-plan, stacks |
| `config/settings.json` | setup | settings lib, start/run |
| `config/profiles.json` | setup | profiles, CI |
| `config/decisions.json` | setup dependencies | setup replay |
| `config/ci.json` | setup ci, ops ci | ci.sh, ssh |
| `generated/discovery.json` | discovery | setup merge |
| `generated/run-plans/*.json` | run, show | debugging, future runners |
| `secrets/ci.env` | ops ci env | deploy credentials (local) |

## Migration

Runtime prefers `config/` when present; falls back to `.ops.yaml`. Use `ops setup export-yaml --apply` and `ops setup import-yaml --apply` to sync between formats.

## Sync commands

| Command | Direction |
| --- | --- |
| `ops setup export-yaml --apply` | `.ops.project/config` → `.ops.yaml` |
| `ops setup import-yaml --apply` | `.ops.yaml` → `.ops.project/config` |

Source: `core/lib/manifest_sync.sh`

## See also

- [../architecture.md](../architecture.md)
- [../README.md](../../README.md)
