# Setup module: run-plans

## Purpose

Regenerates `.ops.project/generated/run-plans/*.json` from the current service
config without starting or running services.

## CLI / entrypoints

```bash
ops setup run-plans
ops setup run-plans --apply
ops setup run-plans --actions=start,status --apply
ops setup --module=run-plans --apply
```

## Source files

- `core/commands/setup.sh` — `_run_run_plans`
- `core/lib/run_plan.sh` — run-plan resolution and JSON writer

## Inputs and outputs

**Reads:** `.ops.project/config/services.json` or `.ops.yaml`.

**Writes with `--apply`:**

| Path | Description |
| --- | --- |
| `.ops.project/generated/run-plans/<service_id>.<action>.json` | Resolved action plan |

Without `--apply`, prints the plans that would be written.

## Actions

By default, the module prepares common lifecycle actions:

```text
start status build test lint logs stop
```

Use `--action=<name>` or `--actions=a,b,c` to narrow the set.

## Testing

```bash
./ops.sh setup run-plans --actions=start,status
./ops.sh setup run-plans --actions=start,status --apply
```
