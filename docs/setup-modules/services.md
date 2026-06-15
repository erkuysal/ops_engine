# Setup module: services

## Purpose

Discovers runtime service candidates, previews merge with existing project
config, and applies discovery-backed service definitions to
`.ops.project/config`.

## CLI / entrypoints

```bash
ops setup services
ops setup services --apply
ops setup apply-services --apply
ops setup --module=services --apply
```

Note: the CLI alias `services` maps to subcommand `apply-services` in `setup.sh`.

## Source files

- `core/commands/setup.sh` — `_run_apply_services`, `_run_discovery`, `_materialize_project_config_from_discovery`
- `core/lib/discovery.sh` — workspace scan
- `core/probes/` — stack fingerprinting

## Inputs and outputs

**Reads:**

- Workspace tree (via discovery)
- Existing `.ops.project/config/services.json` when present
- `.ops.yaml` only as compatibility fallback when project config is absent

**Writes (with `--apply`):**

| Path | Description |
| --- | --- |
| `.ops.project/generated/discovery.json` | Discovery cache |
| `.ops.project/config/services.json` | Runtime service config |
| `.ops.project/config/project.json`, `settings.json`, `profiles.json` | From discovery materialization |
| `.ops.project/generated/setup.json` | Generated setup snapshot |

Preserves confirmed user fields where possible during merge.

## Behavior

1. Runs discovery scan.
2. Prints preview of services added/removed/updated.
3. With `--apply`, materializes config. Use `ops setup export-yaml --apply`
   separately when a YAML compatibility export is needed.

Go `process_group` services get process-level decisions via `_resolve_process_decisions_json` during full setup paths.

## Extension points

- New stacks: add probe + stack + validation; see [extending/new-stack.md](../extending/new-stack.md).
- Role classification: `core/lib/discovery.sh` (`workspace_root`, `shared_library`, etc.).

## Testing

```bash
./ops.sh setup services
./ops.sh setup discover
./ops.sh setup services --apply
./ops.sh validate --plain
```

## See also

- [../core/discovery.md](../core/discovery.md)
- [dependencies.md](dependencies.md)
