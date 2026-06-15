# backup library

## Purpose

Manifest backup helpers used by YAML sync paths.

## Source files

- `core/lib/backup.sh`

## Key functions

- `ops_backup_manifest`
- `ops_backup_list`
- `ops_backup_restore`

## Inputs and outputs

**Writes:** timestamped manifest copies under `.ops.project/.history/`

Config snapshots are handled by the `backup` command.

## See also

- [../commands/setup.md](../commands/setup.md)
- [../commands/backup.md](../commands/backup.md)
