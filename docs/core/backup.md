# backup library

## Purpose

Backup files before mutating setup outputs (`.ops.project/.history/`).

## Source files

- `core/lib/backup.sh`

## Key functions

`_backup_file` in setup.sh delegates here for config/manifest writes.

## Inputs and outputs

**Writes:** timestamped copies under `.ops.project/.history/`

## See also

- [../commands/setup.md](../commands/setup.md)
