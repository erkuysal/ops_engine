# Ops Project Aims

This document defines the intended direction for `ops`: a project-independent orchestration system that can be installed once on a machine, then used inside any repository to discover, configure, run, and manage that project.

The current implementation already contains useful pieces: stack probes, config validation, runtime state under `.ops.project`, service runners, stack strategies, and cross-shell helpers. The next phase is to reorganize those pieces around a clearer product model.

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

## Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md) — how to change the package
- [docs/architecture.md](docs/architecture.md) — discovery, setup, config, and runtime data flow
- [docs/README.md](docs/README.md) — full module documentation index

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
- export or import `.ops.yaml` only as an explicit compatibility format while needed
- enter an interactive flow when required values are ambiguous or missing

`setup` should be idempotent. Re-running it should preserve confirmed project decisions, update stale discovery facts, and ask only about new or unresolved ambiguity.

Setup should feel like modern framework initializers: running bare `ops setup`
in a terminal should open a guided interactive sequence that asks which modules
to run, applies selected changes when confirmed, and falls back to a preview in
non-interactive shells.

Setup should also be modular and lightweight. Explicit module commands should
remain deterministic and scriptable, while individual modules can be run
directly:

```bash
ops setup
ops setup all
ops setup project
ops setup services
ops setup dependencies
ops setup ci
```

The `project` module is the base module. It owns creation of `.ops.project` and the minimum directory/config structure needed by other modules. Other modules may call it automatically when applying changes.

### Runtime Commands

Runtime commands such as `ops start`, `ops stop`, `ops run`, `ops show`, and `ops logs` should consume project state created by `ops setup`.

They should not rediscover the whole project on every run.

They should prefer `.ops.project` config/state first. They may fall back to
`.ops.yaml` only for compatibility projects that have not materialized config
yet.

### `ops ci`

`ci` owns local CI/deploy readiness, server connection metadata, and optional hosted-CI bridges.

It should:

- store server/repository/registry metadata in `.ops.project/config/ci.json`
- support local secrets/config in a private `.ops.project/secrets/ci.env` file
- keep GitHub Actions as optional rather than required
- record expected GitHub Actions secret names only for projects that mirror local config to GitHub
- guide Docker Hub, SSH deploy key, GitHub secret, and server-path setup
- provide doctor checks for local tools and missing server configuration
- preview or generate local deploy SSH keys only when explicitly applied
- print secret setup commands without storing secret values
- check SSH connectivity to the configured server
- eventually generate or validate workflow files from project config

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
    ci.json
  secrets/
    ci.env
  generated/
    discovery.json
    workspace.json
    runtime.json
    run-plans/
      api.start.json
      worker.start.json
    bin/
      worker/
        gateway
        api
        sweeper
        debouncer
  logs/
    api.log
    worker/
      gateway.log
      api.log
  run/
    api.pid
    worker/
      gateway.pid
      api.pid
  .history/
```

### `.ops.yaml`

`.ops.yaml` may remain as:

- a human-editable compatibility format
- an export/import format
- a convenient review surface

`.ops.project/config` is the primary source of truth. YAML is a deliberate
compatibility import/export path.

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

- `services/api/manage.py`
- `services/worker/go.mod`
- `services/worker/cmd/gateway`
- `apps/package.json`
- `apps/web/package.json`
- `apps/desktop/package.json`
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
      "path": "apps",
      "stack": "node",
      "role": "workspace_root",
      "service": false,
      "confidence": 0.95,
      "evidence": ["package.json", "workspaces"]
    },
    {
      "path": "apps/web",
      "stack": "node",
      "role": "app",
      "service": true,
      "confidence": 0.9,
      "evidence": ["package.json", "vite dependency", "dev script"]
    },
    {
      "path": "services/worker",
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

- classify `apps` as a workspace root, not a runnable service
- classify `apps/web` as a Node/Vite app
- classify `packages/api-client` as a shared library
- classify `services/worker` as a Go process group
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

In WSL, `go` may resolve to a shim under `.ops.project/generated/bin/shims`, which points to Windows Go. That should not be treated as native Linux Go. The runner must know:

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
Detected apps as a Node workspace root with child packages.
Use child packages as services and skip apps itself? [Y/n]
```

```text
Detected services/worker has multiple Go cmd entries:
gateway, api, sweeper, debouncer.
Treat this as a process group? [Y/n]
```

```text
Could not infer start command for api.
Choose:
1. python manage.py runserver 0.0.0.0:8000
2. ./start_server.sh
3. custom
```

Confirmed answers should be stored in `.ops.project/config`, so future setup runs do not repeatedly ask.

Dependency interviews should follow the same rule: preserve existing `depends_on` values, ask only in interactive setup flows, store confirmed answers in `.ops.project/config/decisions.json`, and materialize the resulting graph into `.ops.project/config/services.json`.

## Current Gaps

The current implementation does some useful detection, but it is too shallow.

Known remaining gaps:

- Docker Compose dependency inference is still shallow.
- Some stack probes need richer package-manager and framework signals.
- Python/Django runtime handling needs broader conda/venv coverage.
- Some legacy compatibility names remain in helper APIs such as `manifest_*`.
- Documentation and contributor guidance should keep pushing new code toward
  config-first helpers.

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
- Keep `.ops.yaml` export/import compatible with that config
- Runtime commands read `.ops.project/config` first

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

For a representative multi-service repository, setup should infer:

- `services/api` as Django service
- `services/realtime` as Phoenix service
- `services/worker` as Go process group
- `apps` as Node workspace root, not service
- `apps/web` as Node/Vite web app
- `apps/desktop` as Electron/Node app
- `packages/api-client` as shared library or non-runtime package

It should not propose the workspace root itself as a runnable service unless the user explicitly chooses that.

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
