# Runner profiles

## Purpose

Separate **stack** (what the service is: `go`, `node`, `docker`, …) from **runner** (how commands execute).

## Runner kinds

| Kind | Role / trigger | Behavior |
| --- | --- | --- |
| `stack` | Default for `app`, `api`, etc. | Normal override → setup → configured action → stack resolution |
| `process_group` | `process_group` role (e.g. Go `cmd/*`) | Managed by stack dispatcher; overrides and setup start command skipped |
| `compose` | `docker_group` role | Managed by docker stack via `docker compose`; overrides and setup start command skipped |

## Inference

`core/lib/runner.sh` maps discovery role to `runner.kind` during `ops setup discover` / `--apply`.

Existing `runner` blocks in project config are preserved on re-setup. YAML
fallback runner blocks are preserved only when importing or operating before
config is materialized.

## See also

- [action-resolution.md](action-resolution.md)
- [../core/run-plan.md](../core/run-plan.md)
- [../stacks/go.md](../stacks/go.md)
- [../stacks/docker.md](../stacks/docker.md)
