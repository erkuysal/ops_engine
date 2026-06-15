# backup and rollback commands

## Purpose

Snapshot and restore `.ops.project/config/*.json` without touching secrets or
runtime state.

## CLI

```bash
ops backup create --label before-change
ops backup list
ops backup show SNAPSHOT_ID
ops backup diff SNAPSHOT_ID
ops backup prune --keep 20
ops backup prune --keep 20 --apply
ops rollback SNAPSHOT_ID
ops rollback SNAPSHOT_ID --apply
```

## Snapshot Layout

Backups are stored under:

```text
.ops.project/.history/config/<timestamp>-<label>/
  manifest.json
  config/
    project.json
    services.json
    settings.json
    profiles.json
    decisions.json
    monitoring.json
```

Only files that exist at backup time are copied.

## Rollback

`ops rollback SNAPSHOT_ID` previews file status:

- `same`
- `change`
- `add`
- `remove`

`ops rollback SNAPSHOT_ID --apply` creates a `pre-rollback` safety backup before
restoring the snapshot.

## Automatic Backups

`ops setup --apply` creates a `pre-setup` config backup when config files already
exist.

## Pruning

`ops backup prune --keep N` previews old snapshots that would be removed.
`--apply` deletes them.

Secrets under `.ops.project/secrets/` are never included.
