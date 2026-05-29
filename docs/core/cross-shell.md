# cross-shell library

## Purpose

WSL/Windows binary detection, path translation (`wslpath`), and shims for running Windows executables from WSL.

## Source files

- `core/lib/cross_shell.sh`

## Key behavior

- Detects WSL and Windows-hosted tools
- `run_cross_shell_binary` runs Windows executables from WSL with PowerShell + `wslpath` cwd translation
- `ensure_cross_shell_bin` creates shims in project `.ops/bin/` (on PATH via init)
- Used by `core/stacks/go.sh` and `core/stacks/node.sh`

## Do not

Add service-specific path hacks in consuming repos when a cross-shell fix belongs here.

## See also

- [ISSUES/1_CROSS_PLATFORM.md](../../ISSUES/1_CROSS_PLATFORM.md)
- [../stacks/go.md](../stacks/go.md)
