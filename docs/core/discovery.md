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
