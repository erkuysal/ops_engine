# Ops Project Aims

This document defines the intended direction for `ops`: a project-independent orchestration system that can be installed once on a machine, then used inside any repository to discover, configure, run, and manage that project.

The current implementation already contains useful pieces: stack probes, manifest validation, runtime state under `.ops.project`, service runners, stack strategies, and cross-shell helpers. The next phase is to reorganize those pieces around a clearer product model.

## Core Vision

`ops` should be a universal Bash-accessible project orchestrator.

It should:

- install once at the system/user level
- work in any repository without project-specific code
- discover project structure from source files
- create and maintain `.ops.project`
- infer services, run commands, ports, env files, process groups, and runtime requirements when possible
- ask the user interactively only when a value cannot be inferred safely
- store project memory in `.ops.project`
- run services through generic stack and runner abstractions

The long-term goal is for `.ops` itself to remain package-owned and project-independent. Project facts, generated state, runtime plans, logs, PIDs, and local decisions belong in `.ops.project`.

## Command Responsibilities

### `ops install`

`install` is a one-time machine-level command.

Its purpose is to make `ops` callable universally from Bash.

It should eventually:

- install the `ops` command into a user/system bin directory such as `~/.local/bin`, `/usr/local/bin`, or another configured location
- install or update the ops package into a stable user-level location such as `~/.local/share/ops` or `~/.ops`
- record package metadata such as package format, ops core version, source checkout, source revision, install time, and update time
- provide an explicit `ops install update` command that refreshes the installed package from the current ops checkout
- verify required tools and shell compatibility
- repair the global installation when requested
- avoid creating project-specific state unless explicitly asked

`install` should not be the main project initializer. It should prepare the machine so that a user can enter any repo and run `ops setup`.

### `ops setup`

`setup` is the project intelligence command.

Its purpose is to create, update, and validate project-local ops state.

It should eventually absorb most of the responsibilities currently split across `bootstrap`, `init`, and `update`.

It should:

- locate the project root
- create `.ops.project`
- discover the workspace
- classify directories and packages
- infer service definitions
- infer runtime commands
- infer build commands and artifacts
- infer env files and env policy
- infer ports and health checks when possible
- infer service dependencies when possible
- interview and preserve confirmed `depends_on` relationships
- create project config/state under `.ops.project`
- export or maintain `.ops.yaml` only as a compatibility/human-editable layer while needed
- enter an interactive flow when required values are ambiguous or missing

`setup` should be idempotent. Re-running it should preserve confirmed project decisions, update stale discovery facts, and ask only about new or unresolved ambiguity.

### Runtime Commands

Runtime commands such as `ops start`, `ops stop`, `ops run`, `ops show`, and `ops logs` should consume project state created by `ops setup`.

They should not rediscover the whole project on every run.

They should prefer `.ops.project` config/state first. During the migration period, they may fall back to `.ops.yaml`.

## Desired State Layout

`.ops.project` should become the project memory and generated runtime state directory.

Suggested long-term shape:

```text
.ops.project/
  config/
    project.json
    services.json
    profiles.json
    settings.json
  generated/
    discovery.json
    workspace.json
    runtime.json
    run-plans/
      backend.start.json
      userengine.start.json
    bin/
      userengine/
        gateway
        api
        sweeper
        debouncer
  logs/
    backend.log
    userengine/
      gateway.log
      api.log
  run/
    backend.pid
    userengine/
      gateway.pid
      api.pid
  .history/
```

### `.ops.yaml`

`.ops.yaml` may remain during the transition as:

- a human-editable compatibility format
- an export/import format
- a convenient review surface

Long term, `.ops.project/config` can become the primary source of truth.

Potential future commands:

```bash
ops setup export-yaml
ops setup import-yaml
```

## Discovery Model

Setup should separate discovery from resolution.

### Discovery

Discovery answers: what exists in the repository?

Examples:

- `BACKENDs/backend/manage.py`
- `BACKENDs/userengine/go.mod`
- `BACKENDs/userengine/cmd/gateway`
- `frontend/package.json`
- `frontend/web/package.json`
- `frontend/soundilerry/package.json`
- Docker Compose files
- env files
- lockfiles
- pyproject files
- package manager files

Discovery should write raw facts to:

```text
.ops.project/generated/discovery.json
```

Example:

```json
{
  "directories": [
    {
      "path": "frontend",
      "stack": "node",
      "role": "workspace_root",
      "service": false,
      "confidence": 0.95,
      "evidence": ["package.json", "workspaces"]
    },
    {
      "path": "frontend/web",
      "stack": "node",
      "role": "app",
      "service": true,
      "confidence": 0.9,
      "evidence": ["package.json", "vite dependency", "dev script"]
    },
    {
      "path": "BACKENDs/userengine",
      "stack": "go",
      "role": "process_group",
      "service": true,
      "confidence": 0.9,
      "evidence": ["go.mod", "cmd/gateway", "cmd/api"]
    }
  ]
}
```

### Resolution

Resolution answers: what should `ops` do with those facts?

Examples:

- classify `frontend` as a workspace root, not a runnable service
- classify `frontend/web` as a Node/Vite app
- classify `frontend/api_core` as a shared library
- classify `BACKENDs/userengine` as a Go process group
- infer `python manage.py runserver` for Django when no better command is found
- infer Go build outputs from `cmd/*`
- choose Windows Go cross-compile when running in WSL with only Windows Go available
- choose native Linux binaries as runtime artifacts under `.ops.project/generated/bin`

Resolution should produce project config and run plans.

## Roles And Service Classification

Detection should not treat every stack match as a service.

Each discovered directory should receive a role.

Possible roles:

- `app`
- `api`
- `worker`
- `process_group`
- `workspace_root`
- `shared_library`
- `tooling`
- `docker_group`
- `unknown`

Only service-like roles should become runnable services automatically.

Examples:

- Node package with `workspaces`: `workspace_root`, not service
- Node package with Vite dev script: `app`
- Node package with no start/dev/build script and consumed by another package: `shared_library`
- Go module with multiple `cmd/*` entries: `process_group`
- Django project with `manage.py`: `api` or `app`
- Docker Compose file with multiple services: `docker_group`

## Stack And Runner Separation

`ops` should distinguish stacks from runners.

A stack describes what kind of project or service this is.

Examples:

- `go`
- `django`
- `node`
- `elixir-phoenix`
- `docker`

A runner describes where and how commands execute.

Examples:

- native Linux
- native macOS
- WSL shell
- Windows host binary via PowerShell
- Docker container
- Conda environment
- venv environment
- cross-compile from Windows Go to Linux

This distinction matters for cross-OS compatibility.

Example:

In WSL, `go` may resolve to `.ops/bin/go`, which is a shim to Windows Go. That should not be treated as native Linux Go. The runner must know:

- shell OS: WSL/Linux
- tool host OS: Windows
- desired runtime target: Linux
- correct build strategy: `GOOS=linux GOARCH=amd64` through PowerShell

## Interactive Fallback

`setup` should infer aggressively but ask carefully.

It should ask when:

- multiple possible services are found
- a directory could be either workspace root or service
- a start command cannot be inferred
- multiple package managers are plausible
- multiple env files are plausible
- a port cannot be inferred
- dependency relationships are uncertain
- a tool exists but the runner strategy is ambiguous

It should avoid asking when confidence is high.

Example questions:

```text
Detected frontend as a Node workspace root with child packages.
Use child packages as services and skip frontend itself? [Y/n]
```

```text
Detected BACKENDs/userengine has multiple Go cmd entries:
gateway, api, sweeper, debouncer.
Treat this as a process group? [Y/n]
```

```text
Could not infer start command for backend.
Choose:
1. python manage.py runserver 0.0.0.0:8000
2. ./start_server.sh
3. custom
```

Confirmed answers should be stored in `.ops.project/config`, so future setup runs do not repeatedly ask.

Dependency interviews should follow the same rule: preserve existing `depends_on` values, ask only in interactive setup flows, store confirmed answers in `.ops.project/config/decisions.json`, and materialize the resulting graph into `.ops.project/config/services.json`.

## Current Gaps

The current implementation does some useful detection, but it is too shallow.

Known gaps:

- `install` has a first-pass global Bash launcher and stable user-level package copy
- `setup` currently depends on an existing `.ops.yaml`
- `bootstrap`, `init`, and `update` split responsibilities that should move into setup
- detection only emits `id`, `path`, `stack`, and `score`
- detection does not emit role, service/non-service classification, evidence, or confidence
- Node workspace roots can be incorrectly proposed as services
- Go process groups are not inferred automatically from `cmd/*`
- env files are not discovered intelligently
- ports and health checks are not inferred deeply
- `.ops.project` does not yet store a discovery cache
- runtime still primarily reads `.ops.yaml`
- legacy `.scripts` metadata is still richer than `.ops.project` metadata

## Migration Plan

### Phase 1: Clarify Setup As The Project Initializer

- Make `ops setup --dry-run` run discovery even when `.ops.yaml` is missing
- Make `ops setup --apply` create `.ops.project`
- Move or wrap `bootstrap` behavior under setup
- Keep `bootstrap` as a temporary alias

### Phase 2: Add Discovery Cache

- Add `.ops.project/generated/discovery.json`
- Extend probes to emit structured evidence
- Include role, confidence, and service eligibility
- Keep raw scan facts separate from final config decisions

### Phase 3: Improve Stack Probes

Node:

- parse `package.json`
- detect `workspaces`
- classify workspace roots as non-services
- detect Vite/Vue/React/Electron packages
- classify packages without runnable scripts as libraries

Go:

- parse `go.mod`
- inspect `cmd/*`
- infer process groups
- infer build outputs

Django:

- inspect `manage.py`
- detect likely settings module
- infer runserver command
- discover `.env` files

Docker:

- parse compose files
- detect compose service groups
- infer ports and dependencies

### Phase 4: Project Config In `.ops.project`

- Add `.ops.project/config/project.json`
- Add `.ops.project/config/services.json`
- Add `.ops.project/config/settings.json`
- Make `.ops.yaml` export/import compatible with that config
- Runtime commands should read `.ops.project/config` first

### Phase 5: Runtime Plans

- Generate per-action run plans under `.ops.project/generated/run-plans`
- `ops show` should display the selected run plan
- `ops start` and `ops run` should execute the selected run plan

### Phase 6: Global Install

- Convert `ops install` into a real global installer
- Support install, repair, uninstall, and doctor
- Support package version markers and explicit package updates
- Ensure `ops setup` works in any repository after install

## Success Criteria

`ops setup --apply` in a new repository should be able to:

- create `.ops.project`
- discover services and non-service directories
- infer runnable services
- infer start/build/test commands where possible
- write project config
- ask only necessary questions
- generate run plans
- validate the result

For this repository, a successful setup should infer:

- `BACKENDs/backend` as Django service
- `BACKENDs/voice_app` as Phoenix service
- `BACKENDs/userengine` as Go process group
- `frontend` as Node workspace root, not service
- `frontend/web` as Node/Vite web app
- `frontend/soundilerry` as Electron/Node app
- `frontend/api_core` as shared library or non-runtime package

It should not propose `frontend` itself as a runnable service unless the user explicitly chooses that.

## Guiding Principle

`ops` should not know this project by name.

It should know how to reason about project shapes:

- workspace roots
- apps
- APIs
- workers
- process groups
- shared libraries
- runtime environments
- cross-OS runners

The project-specific result should live in `.ops.project`, produced by discovery, resolution, and user confirmation.
