# Legacy compatibility

## Purpose

How older project scripts and commands relate to the orchestrator.

## Parent repo entry

```bash
./ops.sh legacy ...
OPS_USE_LEGACY=true ./ops.sh ...
```

Routes to `.scripts/legacy_entrypoint.sh` instead of `.ops/core/main.sh`.

## Orchestrator bridge

When native stack does not implement an action, `run_plan_legacy_target_script` looks up `scripts/commands.sh` in the **consuming project** and executes bridged deploy/ship scripts.

Full mapping: [core/MIGRATION.md](../../core/MIGRATION.md).

## Compatibility wrappers in package

| Old command | Wrapper | Maps to |
| --- | --- | --- |
| `ops bootstrap` | `core/commands/bootstrap.sh` | `ops setup` |
| `ops update` | `core/commands/update.sh` | `ops setup apply-services` |
| `ops setup init` | setup.sh | interactive generate |

## Preferred path

```bash
ops setup
ops show start <service>
ops start <service>
```

## See also

- [action-resolution.md](action-resolution.md)
- [../commands/bootstrap.md](../commands/bootstrap.md)
