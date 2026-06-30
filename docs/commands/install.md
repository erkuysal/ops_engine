# install command

## Purpose

One-time machine-level install of the global `ops` launcher and packaged copy under `~/.local` (configurable).

## CLI / entrypoints

```bash
ops install [--dry-run] [--force] [--prefix DIR]
ops install doctor
ops install repair
ops install update
ops install uninstall
```

Routed from `core/main.sh` → `core/commands/install.sh`.

From a standalone `.ops` package checkout, bootstrap the project launcher first:

```bash
cd .ops
bash setup
cd ..
./ops.sh install
./ops.sh install doctor
```

## Flags

| Flag | Effect |
| --- | --- |
| `--dry-run` | Show planned install paths |
| `--force` | Overwrite existing install |
| `--prefix` | Base dir (default `~/.local`) |
| `--bin-dir`, `--package-dir` | Override paths |

## Side effects

- Writes `~/.local/bin/ops` (or configured bin dir)
- Copies package to `~/.local/share/ops` (or configured package dir)
- Writes `.ops-install-source` marker with version metadata

Does **not** initialize `.ops.project`.

## Testing

```bash
./ops.sh install doctor
./ops.sh install --dry-run
cd .ops && bash setup
```

## See also

- [../README.md](../../README.md) — Install vs Setup
