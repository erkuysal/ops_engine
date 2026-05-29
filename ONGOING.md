# Ops Ongoing Work

This file tracks active work toward the project aims described in `PROJECT_AIMS.md`.

Use this as the working checklist while evolving `ops`.

## Current Focus

Turn `ops setup` into the project intelligence command.

The immediate goal is:

- `ops setup --dry-run` can discover a project even when `.ops.yaml` is missing
- discovery writes structured facts to `.ops.project/generated/discovery.json`
- setup can distinguish services from workspace roots and shared libraries
- setup can propose project config from discovery
- setup can apply discovery-derived setup into `.ops.project/config`
- runtime helpers can prefer `.ops.project/config` over `.ops.yaml`
- setup asks interactively only for ambiguous values
- setup can bootstrap `.ops.project/config` and a transitional `.ops.yaml` when `.ops.yaml` is absent
- setup can safely merge discovered runtime services back into `.ops.yaml`
- legacy discovery commands route through setup/discovery
- `ops install` installs a global Bash launcher instead of doing project setup
- runtime commands write shared run-plan artifacts before display/execution
- setup can preview/apply dependency decisions into project config
- ops has an initial CI credential/server metadata command
- setup supports lightweight module routing
- bare `ops setup` starts a guided setup sequence when run in a terminal
- ops has a simple SSH connection check command backed by local CI/server config
- `ops ssh --interactive --apply` can set SSH connection values directly
- `ops ssh setup --interactive --apply` saves SSH values without opening a connection
- ops has a focused credential readiness check for Docker, SSH deploy, and GitHub bridge values

## Recently Completed

- **Config sync:** `ops setup export-yaml`, `ops setup import-yaml`, config-first `ops validate` (`core/lib/manifest_sync.sh`).
- **Cross-shell runtime:** `run_cross_shell_binary` wired into Go and Node stacks for WSL + Windows tools.
- **Setup inference:** port inference (Django/Phoenix/Vite), Vite-proxy dependency inference, healthcheck URLs from ports.
- Added contributor documentation: `CONTRIBUTING.md` and comprehensive `docs/` tree (commands, setup modules, core libs, stacks, probes, extending guides).
- Documented project direction in `.ops/PROJECT_AIMS.md`.
- Added `.ops/ONGOING.md` as the active implementation tracker.
- Added structured discovery cache generation:
  - `.ops/core/lib/discovery.sh`
  - `.ops.project/generated/discovery.json`
- Added `ops setup discover`.
- Added discovery preview to `ops setup --dry-run`.
- Improved first-pass role detection:
  - `frontend` is classified as `workspace_root` and skipped by default
  - `frontend/api_core` is classified as `shared_library` and skipped by default
  - `BACKENDs/userengine` is classified as a Go `process_group`
- Clarified desired command responsibilities:
  - `ops install`: global/system install
  - `ops setup`: project initializer/discovery/config generator
  - runtime commands consume `.ops.project`
- Added initial generic Go `process_group` support.
- Updated `userengine` in `.ops.yaml` to use:
  - `runner.kind: process_group`
  - build outputs under `.ops.project/generated/bin/userengine`
- Added cross-shell detection helpers for Windows-hosted tools under WSL.
- Verified Windows Go can cross-compile Linux ELF binaries into `.ops.project`.
- Updated `ops show start userengine` to display the managed Go process group plan.
- Added discovery-derived `.ops.project/config` materialization:
  - `.ops.project/config/project.json`
  - `.ops.project/config/services.json`
  - `.ops.project/config/settings.json`
  - `.ops.project/config/profiles.json`
- Updated `ops setup --apply` to use discovery-derived setup values while preserving confirmed project runtime values.
- Moved setup-generated metadata from root `scripts/` into `.ops.project/generated/`.
- Added config-first readers for services, setup values, and runtime settings.
- Updated `run`, `show`, and the Go process-group stack to use config-backed service data.
- Added setup decision tracking in `.ops.project/config/decisions.json`.
- Added first ambiguity handling for Go process groups:
  - confirmed/existing processes stay enabled
  - discovered webhook-like workers are marked ambiguous
  - ambiguous processes are disabled by default unless interactive setup includes them
- Added no-manifest `ops setup --apply` support that creates `.ops.project/config` and a transitional `.ops.yaml` from discovery.
- Added `ops setup apply-services`:
  - previews discovered runtime services
  - shows services removed from runtime
  - applies the merged service list only with `--apply`
  - preserves confirmed service fields where possible
- Removed `api_core` from the runtime service list because discovery classifies it as a shared library.
- Replaced old `bootstrap`, `init`, and `update` implementations with compatibility wrappers around setup:
  - `bootstrap --dry-run` -> `setup --dry-run`
  - `bootstrap --force` -> `setup apply-services --apply`
  - `init --dry-run` -> `setup apply-services`
  - `init` -> `setup apply-services --apply`
  - `update` -> `setup apply-services`
  - `update --apply` -> `setup apply-services --apply`
- Removed the legacy setup preview from `setup --dry-run`.
- Redesigned `ops install`:
  - `ops install` writes a managed universal `ops` launcher
  - package files are copied into a stable package directory
  - `ops install doctor` checks launcher/source/PATH/shell status
  - `ops install repair` rewrites the managed launcher
  - `ops install update` refreshes the installed package and launcher from the current checkout
  - `ops install uninstall` removes the managed launcher
  - installed package metadata records package format, ops core version, source root, source revision, install time, and update time
  - install is separate from project setup and tells users to run `ops setup --apply` inside projects
  - launcher discovers project-local `.ops/core/main.sh`, otherwise falls back to the installed package core against the current directory
- Added first-pass runtime plan generation:
  - `.ops/core/lib/run_plan.sh`
  - `ops show <action> <service>` writes `.ops.project/generated/run-plans/<service>.<action>.json`
  - `ops run <action> <service>` writes the same kind of plan before execution
  - run plans include config source, selected runner, candidate runners, stack dispatcher, setup values, runtime paths, build outputs, and Go process-group entries
- Updated `ops run` to dispatch from the generated plan's `resolution.selected.strategy`:
  - overrides run from selected override paths
  - setup commands run from the selected setup command
  - stack-backed plans use the selected stack dispatcher
  - legacy bridge plans can run directly from the selected legacy target
- Reintroduced dependency handling under setup:
  - `ops setup dependencies` previews dependency decisions
  - `ops setup dependencies --interactive` interviews service dependencies
  - `ops setup dependencies --apply` writes dependency decisions to `.ops.project/config/decisions.json`
  - selected dependencies are materialized into `.ops.project/config/services.json`
  - setup preserves existing `.ops.yaml` service fields while config is regenerated
- Added basic CI readiness support:
  - `ops ci setup` previews non-secret CI/server metadata
  - `ops ci setup --apply` writes `.ops.project/config/ci.json`
  - `ops ci env --apply` creates `.ops.project/secrets/ci.env` as the local-first secrets/config file
  - `ops ci show` displays configured repository, Docker, deploy, workflow, and expected secret names
  - `ops ci doctor` loads local env config and checks required metadata, local SSH key presence, and local tools
  - `ops ci credentials` checks Docker/env/auth, SSH deploy key/config, and optional GitHub bridge readiness
  - `ops credentials` aliases the same focused credential check
  - `ops ci connect` previews or runs an SSH server check from local env/config
  - `ops ssh` aliases the same lightweight SSH connection check
  - `ops ssh --interactive --apply` prompts for deploy host/user/path/key and saves them
  - `ops ssh setup --interactive --apply` saves the same values without running SSH
  - `ops ci secrets` prints GitHub Actions secret setup guidance without exposing secret values
  - `ops ci ssh-key` previews or generates a deploy SSH key with `--apply`
  - CI doctor checks configured GitHub workflow files exist
  - GitHub Actions is optional; local env + SSH is the primary flow
- Added modular setup routing:
  - bare `ops setup` opens the guided interactive setup sequence in terminals
  - `ops setup all` keeps the current full setup flow
  - non-interactive bare `ops setup` keeps preview behavior
  - `ops setup project` creates/previews base `.ops.project` structure
  - `ops setup services` aliases discovery-backed service setup
  - `ops setup dependencies` remains the dependency module
  - `ops setup ci` runs CI config/env setup through the setup entry point
  - `--module=project|services|dependencies|ci|all` is supported
  - `ops setup interactive` and bare `ops setup --interactive` route to the guided sequence

## Active Problems

### 1. Config-first migration (mostly done)

**Done recently:**

- `ops setup --apply` writes `.ops.project/config` by default; `.ops.yaml` is opt-in via `--export-yaml --apply`
- `ops setup export-yaml --apply` writes `.ops.yaml` from `.ops.project/config`
- `ops setup import-yaml --apply` materializes config from `.ops.yaml`
- `ops validate` validates JSON config directly when no `.ops.yaml` exists
- Runtime commands accept config-only projects via `require_manifest_or_config`
- `confirmed` decisions are tracked in `decisions.json` and respected on re-setup; apply marks decisions confirmed when interactive or `--confirm-inferred`

**Still open:**

- Gradually retire transitional `.ops.yaml` references in docs and legacy setup paths

### 2. Discovery and setup intelligence (in progress)

**Done recently:**

- Structured discovery with roles, confidence, and evidence
- Node workspace roots and shared libraries classified
- Go `process_group` discovery from `cmd/*`
- Port inference for Django (8000), Phoenix (4000), Vite (5173), and dev-script ports
- Dependency inference from Vite proxy targets and dev-script localhost references
- Healthcheck URLs derived from inferred ports during service materialization

**Still open:**

- Deeper env file discovery
- Docker Compose service groups and compose-native dependencies
- Richer framework/package-manager signals in probes
- Dependency interview parity with legacy `init` flows

### 3. Cross-platform runtime (in progress)

**Done recently:**

- `run_cross_shell_binary` in `core/lib/cross_shell.sh`
- Go and Node stacks route through cross-shell execution under WSL + Windows tools
- Windows Go cross-compile path for process groups (`windows_go_build_linux`)

**Still open:**

- Broader runtime coverage (Python/Django conda paths, Rust, etc.)
- Remove remaining project-specific command overrides once generic paths are verified
- Document limitations in README operator guide

### 4. Legacy and compatibility

**Status:** manageable

- `bootstrap`, `init`, and `update` delegate to setup-backed commands
- Legacy deploy bridge remains for ship/build/deploy actions
- Prefer native stacks and `.ops.project` config for dev workflows

## Recently Completed (implementation slices)

- **Slice A — Config sync:** `manifest_sync.sh`, export/import-yaml, config-first validate
- **Slice B — Cross-shell:** `run_cross_shell_binary`, Go/Node stack integration
- **Slice C — Setup inference:** port inference, Vite proxy dependency inference, setup port merge fix
- **Contributor docs:** `CONTRIBUTING.md` and comprehensive `docs/` tree

## Planned Implementation Slices

### Slice 1: Add Discovery Cache

Create a discovery command/library path that writes:

```text
.ops.project/generated/discovery.json
```

Tasks:

- Add structured discovery functions in `.ops/core/lib/detect.sh` or a new `discovery.sh`.
- Preserve current `detect_scan_project` compatibility for old commands.
- Add `ops setup --dry-run` path that can run discovery without requiring `.ops.yaml`.
- Include evidence and confidence in discovery output.

Status: completed for first pass

Notes:

- `ops setup discover --apply` now writes `.ops.project/generated/discovery.json`.
- Discovery is structured but not yet consumed to generate `.ops.project/config`.
- Existing `bootstrap`, `init`, and `update` still use the old `detect_scan_project` path.

### Slice 2: Improve Node Detection

Tasks:

- Parse `package.json` with `jq`.
- Detect `workspaces`.
- Classify workspace root as `workspace_root`.
- Detect package scripts:
  - `dev`
  - `start`
  - `build`
  - `test`
  - `lint`
- Detect likely frameworks/deps:
  - Vite
  - Vue
  - React
  - Electron
- Classify no-run-script packages as `shared_library`.

Status: first pass completed

Notes:

- Workspace roots are detected via `package.json.workspaces`.
- Shared libraries are detected through library metadata such as `main`, `types`, `description`, and missing runtime start command.
- More package manager and framework detail still needs to be added.

### Slice 3: Improve Go Detection

Tasks:

- Parse Go module directories.
- Detect `cmd/*` entries.
- If multiple commands exist, classify as `process_group`.
- Infer build outputs from command directory names.
- Store output proposals in discovery.
- Add confidence/evidence.

Status: first pass completed

Notes:

- Go modules with multiple `cmd/*/main.go` entries are classified as `process_group`.
- Build outputs are inferred into discovery.
- Discovery currently sees `worker-webhook`; current runtime config still starts only gateway/api/sweeper/debouncer until we decide whether webhook belongs in local runtime.

### Slice 4: Setup Proposal From Discovery

Tasks:

- Convert `discovery.json` into a proposed project config.
- Skip non-service roles by default.
- Generate services for app/API/process-group roles.
- Preserve existing confirmed decisions.
- Ask questions for ambiguous entries.

Status: first pass completed

Notes:

- `ops setup --dry-run` now prints proposed services and setup sections from structured discovery.
- `ops setup --apply` now writes discovery-derived setup values and `.ops.project/config` files.
- Existing confirmed runtime values such as Python manager/env are preserved during apply.
- `.ops.yaml services` is not rewritten yet; that remains a separate, higher-risk merge step.
- Legacy metadata files are now generated under `.ops.project/generated` instead of root `scripts/`.
- If `.ops.yaml` is absent, `setup --apply` can now create project config and a transitional manifest from discovery.
- Ambiguous process-group outputs are recorded in `.ops.project/config/decisions.json`.
- `ops setup apply-services --apply` now updates `.ops.yaml services` from discovery and skips non-runtime roles.

### Slice 5: `.ops.project/config`

Tasks:

- Create:

```text
.ops.project/config/project.json
.ops.project/config/services.json
.ops.project/config/settings.json
.ops.project/config/profiles.json
```

- Keep writing `.ops.yaml` as compatibility export.
- Add config read helpers that prefer `.ops.project/config`.

Status: first pass completed

Notes:

- Setup now materializes project memory into `.ops.project/config`.
- Runtime helper reads now prefer `.ops.project/config` for service list/fields, setup values, and settings.
- `.ops.yaml` remains the compatibility fallback and validation target for now.
- `ops show` reports when service config is coming from `.ops.project/config/services.json`.
- `.ops.project/config/decisions.json` records setup decisions such as whether a discovered process belongs in local runtime.

### Slice 6: Runtime Plans

Tasks:

- Generate per-action run plans:

```text
.ops.project/generated/run-plans/<service>.<action>.json
```

- Make `ops show` display run plans.
- Make runtime commands execute selected plans.

Status: first pass completed

Notes:

- Run plans are now generated as JSON under `.ops.project/generated/run-plans/`.
- `show` exposes the generated plan path.
- `run` generates the plan before preflight/env materialization and reads core service facts from the generated plan.
- `run` now dispatches from `resolution.selected.strategy` in the generated plan.
- Stack-backed strategies still execute through the stack dispatcher because that is where stack-specific behavior and process groups live.

### Slice 7: Global Install

Tasks:

- Redesign `ops install`.
- Install `ops` globally for Bash.
- Add global install doctor/repair.
- Keep project setup separate from install.

Status: first pass completed

Notes:

- `ops install` now installs a universal Bash launcher into `~/.local/bin` by default.
- `--prefix` and `--bin-dir` are supported.
- `--package-dir` is supported and defaults to `~/.local/share/ops`.
- `doctor`, `repair`, and `uninstall` are implemented.
- Current installer copies the `.ops` package to the package directory and points the launcher there.
- Package metadata is written to `.ops-install-source`.
- `ops install doctor` reports source/package version information.
- `ops install update` refreshes the managed package and rewrites the launcher.
- `ops version` reports installed package metadata when running from a packaged core.

## Verification Commands

Current useful checks:

```bash
bash ops.sh setup discover
bash ops.sh setup discover --apply
bash ops.sh setup --dry-run
bash ops.sh setup project
bash ops.sh setup ci
bash ops.sh ci setup
bash ops.sh ci doctor
bash ops.sh show start userengine
bash ops.sh start userengine --dry-run
bash ops.sh run build userengine
bash ops.sh validate --plain
```

Discovery previews:

```bash
bash ops.sh bootstrap --dry-run
bash ops.sh init --dry-run --no-deps
bash ops.sh update
```

Known current issue:

```text
Dependency inference is heuristic (Vite proxy + dev-script ports). Review with
`ops setup dependencies` before `--apply`. Interactive mode still overrides inference.
```

## Open Decisions

- Should `.ops.project/config` use one combined `project.json` or split files?
- Should `.ops.yaml` be generated by default after setup, or only when requested?
- Should setup always create `.ops.project`, even in dry-run mode?
- How should confirmed interactive answers be represented?
- Should global `ops install` copy the whole package or reference a source checkout?
- Should process group runtime support per-process env overrides in the first pass?
- Should shared libraries like `api_core` be included in config as non-runtime nodes?

## Notes

Keep `.ops` package code project-independent.

Project-specific facts should be discovered, inferred, or asked for, then stored in `.ops.project`.

Avoid adding new service-specific override scripts when a generic stack/runner capability can represent the behavior.
