# Config files reference

## Purpose

Layout of `.ops.project` — project memory and generated runtime state.

## Directory tree

```text
.ops.project/
  .gitignore
  .history/              # config snapshots and compatibility export backups
    config/
      <timestamp>-<label>/
        manifest.json
        config/
  config/
    project.json
    services.json
    settings.json
    profiles.json
    decisions.json
    ci.json
    monitoring.json
  generated/
    discovery.json
    setup.json
    project_structure.json
    project_values.json
    run-plans/
      <service>.<action>.json
    bin/                   # e.g. Go process_group builds and cross-shell shims
  logs/
  profiles/
  run/                     # PID files
  secrets/
    ci.env                 # local only, gitignored
    infra.env              # local infra monitor secrets, gitignored
```

## File roles

| File | Written by | Consumed by |
| --- | --- | --- |
| `config/project.json` | setup project / materialize | setup lib, runtime |
| `config/services.json` | setup services | manifest lib, run-plan, stacks |
| `config/monitoring.json` | ops monitor setup / optional manual target config | monitor command |
| `config/settings.json` | setup | settings lib, start/run |
| `config/profiles.json` | setup | profiles, CI |
| `config/decisions.json` | setup dependencies | setup replay |
| `config/ci.json` | setup ci, ops ci | ci.sh, ssh |
| `.history/config/<id>/` | ops backup create, ops rollback --apply safety backup | rollback |
| `generated/discovery.json` | discovery | setup merge |
| `generated/run-plans/*.json` | run, show | debugging, future runners |
| `secrets/ci.env` | ops ci env | deploy credentials (local) |
| `secrets/infra.env` | ops monitor setup | Postgres/Redis monitor credentials (local) |

## Compatibility YAML

Runtime prefers `config/` when present. `.ops.yaml` is optional compatibility
I/O for projects or tools that still need YAML. Use
`ops setup export-yaml --apply` and `ops setup import-yaml --apply` to move
between formats deliberately.

## Sync commands

| Command | Direction |
| --- | --- |
| `ops setup export-yaml --apply` | `.ops.project/config` → `.ops.yaml` |
| `ops setup import-yaml --apply` | `.ops.yaml` → `.ops.project/config` |

## Version-control policy

- Keep `config/` and intentionally shared `profiles/` reviewable.
- `config/ci.json.global_profile` is a portable index into the current
  machine's `${XDG_CONFIG_HOME:-~/.config}/ops/profiles/<id>.json`; global
  connection metadata and credential references are not copied into projects.
- Ignore `generated/`, `logs/`, `run/`, `secrets/`, and `.history/`.
- Regenerate missing discovery, run-plan, environment, shim, and binary outputs
  rather than restoring them from Git.
- Use `ops backup` for local config snapshots; backup history is not repository
  source.

Source: `core/lib/manifest_sync.sh`

## See also

- [../architecture.md](../architecture.md)
- [../README.md](../../README.md)
