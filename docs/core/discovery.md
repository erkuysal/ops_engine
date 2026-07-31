# discovery library

## Purpose

Structured workspace discovery: scan directories, score stack probes, classify roles, emit `discovery.json`.

## Source files

- `core/lib/discovery.sh` — `discovery_scan_project_json`, node builders
- `core/lib/detect.sh` — ignore patterns, directory walking
- `core/probes/*.sh` — stack fingerprint scoring

## Inputs and outputs

**Reads:** project tree under `OPS_PROJECT_ROOT`.

**Writes:**

| Path | Description |
| --- | --- |
| `.ops.project/generated/discovery.json` | Cached discovery (`OPS_DISCOVERY_FILE`) |

## Behavior

- Classifies entries: `app`, `workspace_root`, `shared_library`, `process_group`, etc.
- Invokes `probe_<stack>_score_dir` for each candidate directory.
- Node/Go/Django/Phoenix-specific evidence in `_discovery_*_json` helpers.
- Standard compose filenames under a detected service path are recorded in
  `compose_files`; pure Docker/Compose directories still become `docker_group`
  services.
- A root Compose stack is detected independently of a root Node workspace. It
  becomes a project-named `docker_group` service (or `<name>-compose` on an ID
  collision), and a root `deployment/compose/production.yml` is paired with
  the base Compose file.
- NestJS services default to port 3000 for development dependency inference;
  this lets a Vite proxy targeting port 3000 infer its backend dependency.
- Setup infers `runner.kind: compose` for `docker_group` roles and `process_group` for multi-binary Go services.
- Env file discovery via `core/lib/env_discovery.sh` (service `env_files`, project `global_env_files`).

## Extension points

Add a probe script and wire scoring in `discovery.sh`. See [extending/new-probe.md](../extending/new-probe.md).

## Testing

```bash
./ops.sh setup discover
cat .ops.project/generated/discovery.json | jq .
```

## See also

- [probes.md](probes.md)
- [../setup-modules/services.md](../setup-modules/services.md)
