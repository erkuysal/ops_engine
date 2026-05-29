# preflight library

## Purpose

Pre-execution checks: required binaries, paths, and environment before running a service action.

## Source files

- `core/lib/preflight.sh`

## Used by

- `core/commands/run.sh`

## Exit codes

Run command uses exit code `3` for preflight failures (see `run.sh` header).

## See also

- [../commands/run.md](../commands/run.md)
