# Cross-Platform Binary Execution (WSL/Windows)

## Problem

When ops runs inside WSL but a required tool is installed on Windows, path and
working-directory translation can break. For example, Windows Go cannot
directly consume WSL paths such as `/mnt/d/...` unless ops translates the
working directory and output paths.

## Boundary Rule

Cross-shell fixes belong in generic ops libraries and stack handlers, not in
service-specific command overrides.

Avoid:

- hardcoded service names
- hardcoded project paths
- committed machine-local executable shims
- one-off overrides for behavior every project using that stack may need

## Current Package Support

- `core/lib/cross_shell.sh` detects WSL and Windows-hosted tools.
- `run_cross_shell_binary` runs Windows executables from WSL with PowerShell and
  `wslpath` working-directory translation.
- `ensure_cross_shell_bin` can generate machine-local shims under
  `.ops.project/generated/bin/shims`.
- Go and Node stacks route through cross-shell execution.
- Go process-group builds can use Windows Go to cross-compile Linux binaries
  into `.ops.project/generated/bin/<service_id>`.

## Remaining Work

- Broader stack coverage, especially Python/Django environment activation and
  future Rust support.
- Tests for Windows binary detection under WSL.
- Tests for path conversion behavior.
- Remove any remaining service-specific cross-shell overrides when generic stack
  behavior covers the case.

## Success Criteria

- Any Go service can use Windows Go from WSL without service-specific code.
- Cross-shell shims are generated only under `.ops.project`, never committed in
  `.ops`.
- Native Linux and macOS toolchains continue to work unchanged.
- Documentation explains the behavior in `docs/core/cross-shell.md`.

## Related Files

- `core/lib/cross_shell.sh`
- `core/stacks/go.sh`
- `core/stacks/node.sh`
- `core/lib/preflight.sh`
- `docs/core/cross-shell.md`
