# manifest library

## Purpose

Config-first service and project accessors. The historical `manifest_*` names
remain for compatibility, but new runtime code should use the `project_*`
aliases. Both layers prefer `.ops.project/config` and fall back to `.ops.yaml`
only when config is absent.

## Source files

- `core/lib/manifest.sh`

## Key functions

| Function | Role |
| --- | --- |
| `require_manifest` | Fail if an explicit YAML compatibility source is required but missing |
| `manifest_exists` | Check `.ops.yaml` presence |
| `require_manifest_or_config` | Require project config or YAML fallback |
| `project_require_config_or_yaml` | Config-neutral alias for runtime/project commands |
| `project_config_services_exists` | Check `.ops.project/config/services.json` presence |
| `project_config_exists` | Config-neutral alias for service config presence |
| `manifest_list_services` | List service IDs from config first |
| `project_list_services` | Preferred alias for new code |
| `manifest_get_service_field` | Read nested service field from config first |
| `project_get_service_field` | Preferred alias for new code |
| `manifest_get_service_list_field` | Read list fields from config first |
| `project_get_service_list_field` | Preferred alias for new code |
| `project_service_exists` | Preferred alias for service existence checks |
| `project_get_field` | Preferred alias for project-level fields |
| `project_global_env_files` | Read project-level env files from config first |

## Inputs and outputs

**Reads:** `.ops.project/config/project.json`, `.ops.project/config/services.json`, and `.ops.yaml` fallback.

## Extension points

New runtime code should use the `project_*` helpers. Keep `manifest_*` calls in
legacy paths until touched for other reasons, and do not call
`require_manifest` unless the command is explicitly about YAML import/export.

## See also

- [../reference/config-files.md](../reference/config-files.md)
- [run-plan.md](run-plan.md)
