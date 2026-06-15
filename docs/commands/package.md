# package command

## Purpose

Inspect the `.ops` package checkout, Git state, and installed package metadata.

## CLI / entrypoints

```bash
ops package status
ops package status --json
```

## Source files

- `core/commands/package.sh`

## Behavior

Reports:

- package root
- core version from `core/main.sh`
- Git availability and backend (`git` or `wsl-git`)
- branch, revision, commit date
- dirty and untracked file counts
- installed package marker metadata when `.ops-install-source` exists

The command degrades gracefully when Git is unavailable from the current shell.

## Testing

```bash
bash tests/run.sh
./ops.sh package status
```
