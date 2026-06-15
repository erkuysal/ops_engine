# Package boundaries

## Purpose

Keep `.ops/` reusable across repositories. Project-specific facts belong outside the package.

## Ownership table

| Path | Owner | Purpose |
| --- | --- | --- |
| `.ops/` | ops package | Commands, libraries, stack strategies, probes, schemas, docs |
| `.ops.project/` | project (generated) | Config, discovery cache, run plans, logs, PIDs, backups, secrets |
| `.ops.yaml` | project (optional) | Compatibility export/import of `.ops.project/config` |
| `ops.sh` | consuming repo | Entrypoint that invokes the local `.ops` package |

## Rules for contributors

**Do**

- Add generic stack/probe/discovery logic under `.ops/core/`.
- Store confirmed project decisions under `.ops.project/config/`.
- Use discovery + setup to infer ports, commands, and dependencies.
- Put optional per-project command overrides under the **project** tree: `.ops/commands/<service>/<action>.sh` (project-local `.ops/`, not the package submodule).

**Do not**

- Hardcode service names, paths, or hostnames in package files under `.ops/`.
- Commit secrets into the ops package repo.
- Add project-only workarounds in `core/stacks/` when a stack-level or cross-shell fix is the right abstraction (see [ISSUES/1_CROSS_PLATFORM.md](../ISSUES/1_CROSS_PLATFORM.md)).

## Project-local overrides (consuming repo)

These live next to the project root, not inside the ops git submodule:

```text
<project>/.ops/commands/<service_id>/start.sh   # service override
<project>/.ops/commands/start.sh                # global override
```

Run-plan resolution checks these before stack defaults. See [reference/action-resolution.md](reference/action-resolution.md).

## Generated vs hand-edited

| Location | Typical edit |
| --- | --- |
| `.ops.project/generated/` | Machine-written; safe to regenerate |
| `.ops.project/config/` | Primary project facts; written by setup and explicit config commands |
| `.ops.project/secrets/` | Local only; gitignored |
| `.ops.yaml` | Optional compatibility export/import; not written by default |

## See also

- [architecture.md](architecture.md)
- [reference/config-files.md](reference/config-files.md)
- [../README.md](../README.md) — operator-facing boundaries section
