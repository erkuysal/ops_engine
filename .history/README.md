# .ops/.history/

Timestamped backups of `.ops.yaml` created automatically before any mutating
orchestrator operation (`init`, `update`, `restore`).

Files are named `<ISO-timestamp>.yaml` and pruned to the last 50 entries.

To restore a backup, run:
```sh
./ops.sh experimental restore <timestamp>
```
(available in Phase 7)
