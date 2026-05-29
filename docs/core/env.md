# env library

## Purpose

Environment broker: resolve env files, policies, and service context for execution.

## Source files

- `core/lib/env.sh`

## CLI / entrypoints

Used by `core/commands/env.sh` and `run.sh`.

## Key behavior

- Applies `env_policy` per service and project (`dev_file`, `ci_system`, etc.)
- Respects `global_env_files` from project config
- Exports context for stack dispatch (`OPS_SERVICE_ID`, cwd, env files)

## See also

- [env-materialize.md](env-materialize.md)
- [../commands/env.md](../commands/env.md)
