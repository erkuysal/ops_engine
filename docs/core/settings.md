# settings library

## Purpose

Read runtime settings from config or manifest (modes, preview lines, dependency defaults).

## Source files

- `core/lib/settings.sh`

## Key functions

| Function | Role |
| --- | --- |
| `ops_setting_mode` | String setting with default |
| `ops_setting_bool` | Boolean setting |
| `ops_setting_int` | Integer setting |

## Inputs and outputs

Reads `.ops.project/config/settings.json` with `.ops.yaml` `settings:` fallback.

## See also

- [../reference/config-files.md](../reference/config-files.md)
- [../commands/start.md](../commands/start.md)
