# run-plan library

## Purpose

Resolve how an action runs for a service, emit JSON run plans, and write artifacts under `.ops.project/generated/run-plans/`.

## Source files

- `core/lib/run_plan.sh`

## Key functions

| Function | Role |
| --- | --- |
| `run_plan_generate_json` | Build full resolution JSON |
| `run_plan_write_json` | Persist `run-plans/<service>.<action>.json` |
| `run_plan_file` | Path helper |
| `run_plan_stack_default_command` | Stack/action defaults |
| `run_plan_legacy_target_script` | Legacy `scripts/commands.sh` lookup |

## Resolution order

Implemented in `run_plan_generate_json` (highest wins):

1. `runner.kind: process_group` → stack dispatcher
2. Service override `.ops/commands/<id>/<action>.sh` (executable)
3. Global override `.ops/commands/<action>.sh` (executable)
4. Setup start command (start only)
5. Manifest `actions.<action>`
6. Stack default command
7. Legacy bridge script
8. Unresolved

Full detail: [../reference/action-resolution.md](../reference/action-resolution.md).

## Inputs and outputs

**Reads:** config/services, manifest, overrides, stack files.

**Writes:** `.ops.project/generated/run-plans/<service_id>.<action>.json`

## Testing

```bash
./ops.sh show start <service_id>
jq . .ops.project/generated/run-plans/<service_id>.start.json
```

## See also

- [../commands/run.md](../commands/run.md)
- [stacks.md](stacks.md)
