# manifest library

## Purpose

Config-first service and project accessors. The `project_*` functions own the
runtime implementation. Historical `manifest_*` names remain as compatibility
wrappers. Both layers prefer `.ops.project/config` and fall back to `.ops.yaml`
only when config is absent.

## Source files

- `core/lib/manifest.sh`

## Key functions

| Function | Role |
| --- | --- |
| `require_manifest` | Fail if an explicit YAML compatibility source is required but missing |
| `manifest_exists` | Check `.ops.yaml` presence |
| `project_require_config_or_yaml` | Require project config or YAML fallback |
| `project_config_services_exists` | Check `.ops.project/config/services.json` presence |
| `project_config_exists` | Check service config presence |
| `project_list_services` | List service IDs |
| `project_get_service_field` | Read a nested scalar service field |
| `project_get_service_list_field` | Read a list field, one value per line |
| `project_get_service_json_field` | Read any service field as compact JSON |
| `project_service_exists` | Check service existence |
| `project_get_field` | Read project-level fields |
| `project_global_env_files` | Read project-level env files from config first |
| `manifest_*`, `require_manifest_or_config` | Legacy compatibility wrappers |

## Inputs and outputs

**Reads:** `.ops.project/config/project.json`, `.ops.project/config/services.json`, and `.ops.yaml` fallback.

## Extension points

New runtime code should use the `project_*` helpers. Keep `manifest_*` calls in
legacy setup/migration paths only, and do not call `require_manifest` unless the
command is explicitly about YAML import/export or a YAML-only fallback.

## See also

- [../reference/config-files.md](../reference/config-files.md)
- [run-plan.md](run-plan.md)
