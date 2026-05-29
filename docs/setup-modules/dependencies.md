# Setup module: dependencies

## Purpose

Previews and applies service dependency decisions (`depends_on`) into project config, using discovery facts and optional interactive prompts.

## CLI / entrypoints

```bash
ops setup dependencies
ops setup dependencies --interactive --apply
```

## Source files

- `core/commands/setup.sh` — `_run_dependencies`, `_resolve_dependency_decisions_json`, `_resolve_setup_decisions_json`, `_print_dependency_decisions_preview`
- `core/lib/graph.sh` — dependency graph helpers (runtime)

## Inputs and outputs

**Reads:**

- `discovery.json` (from scan or cache)
- Existing `decisions.json`, manifest `depends_on`

**Writes (with `--apply`):**

| Path | Description |
| --- | --- |
| `.ops.project/config/decisions.json` | Confirmed setup decisions |
| `.ops.project/config/services.json` | Updated `depends_on` per service |
| `.ops.project/generated/discovery.json` | Refreshed cache |
| `.ops.project/generated/setup.json` | Setup snapshot |

## Behavior

1. Ensures project base when applying.
2. Resolves dependency decisions (preserved values, **inferred** from Vite proxy targets and dev-script localhost ports, or interactive when `--interactive`).
3. Prints preview via `_print_dependency_decisions_preview`.
4. Materializes config on `--apply`.

Inference requires inferred service ports in setup JSON (Django 8000, Phoenix 4000, Vite 5173, etc.). Existing manifest `port: 0` does not block inferred ports during merge.

## Extension points

Extend `_resolve_dependency_decisions_json` or discovery hints for new dependency signals.

## Testing

```bash
./ops.sh setup dependencies
./ops.sh setup dependencies --interactive --apply
```

## See also

- [../core/graph.md](../core/graph.md)
- [services.md](services.md)
