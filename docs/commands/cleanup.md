# cleanup command

## Purpose

Preview or remove explicitly selected runtime, generated-state, or local Docker
image cleanup targets.

## CLI / entrypoints

```bash
ops cleanup
ops cleanup --pids --apply
ops cleanup --logs-older-than=30
ops cleanup --logs-older-than=30 --apply
ops cleanup images --repository=example/app --min-version=1.2.3
ops cleanup generated
```

## Source files

- `core/commands/cleanup.sh`
- `core/lib/cleanup.sh`

## Behavior

Without flags, `ops cleanup` previews stale PID files under `.ops.project/run`.
Every category is preview-only unless `--apply` is passed.

Log cleanup is opt-in and age-based:

```bash
ops cleanup --logs-older-than=30 --apply
```

Local image cleanup only inspects tags whose repository exactly matches the
requested name. Normal numeric semantic-version comparison is the default:

```bash
ops cleanup images \
  --repository=example/app \
  --min-version=1.2.3
```

Apply removes the exact `repository:tag` reference, not an image ID, so another
tag pointing at the same image is not removed accidentally.

`--version-rule=patch-first-digit` exists only for compatibility with the
repository's former standalone `cleaner.sh`. Under that rule, patch `71`
compares as `7`. New usage should keep the default `semver` rule.

Generated cleanup is explicit and limited to rebuildable files under
`.ops.project/generated`:

```bash
ops cleanup generated
ops cleanup generated --apply
```

It never targets `.ops.project/config`, `profiles`, `secrets`, or `.history`.
Configuration backups are managed separately with `ops backup prune`.

## Testing

```bash
bash tests/run.sh
./ops.sh cleanup
```
