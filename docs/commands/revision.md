# revision command

## Purpose

Record what was deployed, when, by whom and where, so "what is running on the
server?" has an answer without guessing from image timestamps. Git is optional.

## CLI / entrypoints

```bash
ops revision show [--message=TEXT] [--target=NAME] [--json]
ops revision record [--target=NAME] [--message=TEXT] [--allow-dirty] [--remote] [--path=DIR] [--dry-run] [--json]
ops revision current [--path=DIR] [--json]
ops revision history [--remote] [--path=DIR] [--limit=N] [--json]
```

`ops deploy` records automatically (see [deploy.md](deploy.md)). Call
`ops revision record --remote` yourself from a project's own deploy script when
it does not deploy through `ops deploy`, for example one that syncs files with
rsync before running compose.

## Source files

- `core/commands/revision.sh`
- `core/lib/revision.sh`

## Behavior

A record is one JSON object:

| Field | Meaning |
| --- | --- |
| `id` | `<UTC time>-<short commit>`, or `<UTC time>-nogit` |
| `source` | `git` or `none` |
| `commit`, `short`, `branch`, `subject` | From git; `null` without git |
| `dirty`, `changed_files` | Uncommitted changes, untracked files included (sync deploys copy them). `.ops.project/` is ignored. `null` without git |
| `message` | The operator's `--message`, or `null` |
| `target` | `--target` label such as `staging`, or `null` |
| `project`, `deployed_at`, `deployed_by` | Project name, UTC time, `user@host` |
| `remote`, `deploy_path` | Where it was deployed (set by `--remote` and `ops deploy`) |
| `ops_version` | The ops core version that wrote it |

Where records go:

| File | What |
| --- | --- |
| `.ops.project/.history/deploys.jsonl` | Every record made from this machine (git-ignored local state) |
| `DEPLOY_PATH/.ops-revision.json` | The current deploy on the server, replaced atomically |
| `DEPLOY_PATH/.ops-deploys.jsonl` | Every deploy to that path, from any machine |

The history files are append-only JSON Lines, so `tail`, `jq -s` and `grep`
work on them directly. Deploy scripts that sync with `rsync --delete` keep the
two server files as long as they are outside the synced include list (rsync
never deletes excluded files).

### Policy

| Situation | Default behavior |
| --- | --- |
| Git, clean tree | Records the commit; no message needed |
| Git, uncommitted changes | Refuses (exit 2) unless `--allow-dirty`; the record then says `dirty: true` |
| No git | Asks for a message in an interactive terminal; otherwise records by time only, with a warning |
| `revision.require_message: true` | A message is required in every case (exit 2 without one) |

Settings, in `.ops.project/config/settings.json` under `settings.revision`:

```json
{ "settings": { "revision": { "enabled": true, "allow_dirty": false, "require_message": false } } }
```

`enabled: false` turns off the automatic record in `ops deploy` (same as
`--no-record`); `ops revision record` still works when called directly.

`ops revision current` reads the server record and reports `same_commit`:
`true`/`false` when both sides have a commit, `null` when either has no git.

The server connection comes from `.ops.project/config/ci.json` and
`.ops.project/secrets/ci.env`. `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PATH` and
`DEPLOY_SSH_KEY_PATH` override it, and `--path` overrides the path.

## Testing

```bash
bash tests/run.sh            # suite_revision uses tests/fixtures/bin/ssh, a fake server
./ops.sh revision show
./ops.sh revision record --dry-run
```
