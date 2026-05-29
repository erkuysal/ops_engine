# init library

## Purpose

Shared bootstrap for all ops scripts: strict mode, path resolvers, error helpers, lockfile, and safety checks.

## CLI / entrypoints

Sourced only — not invoked directly.

```bash
source "${OPS_CORE_ROOT}/lib/init.sh"
```

## Source files

- `core/lib/init.sh`

## Key exports

| Function / variable | Role |
| --- | --- |
| `repo_root` | Project root (contains `ops.sh` or `.ops/core`) |
| `ops_core_root` | `.ops/core` path |
| `manifest_path` | `.ops.yaml` path |
| `OPS_PROJECT_ROOT`, `OPS_CORE_ROOT`, `OPS_MANIFEST` | Exported after bootstrap |
| `die`, `warn`, `info`, `ok`, `debug` | Logging / exit |
| `ops_lock_acquire` / `ops_lock_release` | Mutating command lock |
| `require_within_root` | Path traversal guard |
| `require_bins` | Check external tools |
| `ensure_dir`, `ops_timestamp` | Utilities |

## Inputs and outputs

Sets `OPS_CI`, `OPS_PLAIN`, `OPS_DEBUG` from environment. Adds `${OPS_LOCAL_DIR}/bin` to `PATH` for cross-shell shims.

## Extension points

Add new resolvers here rather than duplicating path logic in commands.

## Testing

Any command sources init; verify with `OPS_DEBUG=true ./ops.sh doctor`.

## See also

- [logger.md](logger.md)
- [../development.md](../development.md)
