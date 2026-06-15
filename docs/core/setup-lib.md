# setup library

## Purpose

Shared setup helpers: profile paths, service field readers, config-first access to `.ops.project/config`, stack default commands.

## Source files

- `core/lib/setup.sh`

## Key functions

| Function | Role |
| --- | --- |
| `setup_default_profile` | Default profile name |
| `setup_profile_file` | Path under `.ops.project/profiles/` |
| `setup_service_get` / `setup_service_start_command` | Per-service setup values |
| `setup_stack_default_command` | Stack + action → default shell command |
| `project_config_*` | Readers for `config/*.json` |
| `setup_runtime_python_activation` | Conda/env activation hints |

## Inputs and outputs

Reads `.ops.project/config/` and falls back to `.ops.yaml` `setup.services`
only when config has not been materialized.

## Extension points

Add config readers when new `config/*.json` files are introduced. New runtime
code should not add direct `yq` reads unless it is explicitly handling YAML
compatibility import/export.

## See also

- [../commands/setup.md](../commands/setup.md)
- [manifest.md](manifest.md)
