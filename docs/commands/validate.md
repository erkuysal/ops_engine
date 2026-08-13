# validate command

## Purpose

Multi-pass validation of project ops config. Validates `.ops.project/config`
directly when present, and falls back to `.ops.yaml` only for compatibility
projects that have not materialized config yet.

## CLI / entrypoints

```bash
ops validate [--plain] [--json]
```

When config exists, validation reads `.ops.project/config` through
`core/lib/config_validate.sh`. It does not generate a temporary YAML manifest.

`--json` prints `{summary: {errors, warnings, hints}, errors: [...], warnings: [...], hints: [...]}`
merged with the shared `ok`/`command` envelope — see
[../reference/json-output.md](../reference/json-output.md). Unlike other
commands, `ok` here reflects whether validation actually passed
(`errors == 0`), matching the exit code — not just whether JSON was produced.
Exit codes are unchanged in `--json` mode (see below).

## Source files

- `core/commands/validate.sh`
- `core/lib/config_validate.sh`, `manifest.sh`, `graph.sh`, `setup.sh`

## Passes

Config source:

1. JSON structure, required sections, and service semantics
2. Filesystem checks for service paths and env files
3. Settings/profile override validation

YAML compatibility source:

1. Syntax — `yq` parses `.ops.yaml`
2. Structural — required keys and types
3. Semantic — duplicate IDs, unknown stacks, `depends_on` refs, env policies
4. Filesystem — service paths and env files exist

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Passed (warnings OK) |
| 1 | Errors found |
| 2 | Missing config/YAML source or required tools |

## Config-only projects

If `.ops.yaml` is absent but `.ops.project/config/services.json` exists,
validate runs against JSON config directly.

## Testing

```bash
./ops.sh validate --plain
```

## See also

- [../core/manifest.md](../core/manifest.md)
