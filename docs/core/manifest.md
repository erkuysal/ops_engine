# manifest library

## Purpose

Read and list services from `.ops.yaml` and config-backed service lists.

## Source files

- `core/lib/manifest.sh`

## Key functions

| Function | Role |
| --- | --- |
| `require_manifest` | Fail if no manifest when required |
| `manifest_exists` | Check `.ops.yaml` presence |
| `manifest_list_services` | List service IDs |
| `manifest_get_service_field` | Read nested service field |
| `manifest_get_service_list_field` | Read list fields (e.g. process names) |

## Inputs and outputs

**Reads:** `.ops.yaml`, optionally `.ops.project/config/services.json` via config-first helpers in setup lib.

## Extension points

When deprecating YAML, extend config readers in `setup.sh` lib rather than scattering `yq` calls.

## See also

- [../reference/config-files.md](../reference/config-files.md)
- [run-plan.md](run-plan.md)
