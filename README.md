# Ops

Ops is a reusable, project-independent orchestration package for multi-service
repositories.

The direction is simple:

- `.ops/` is the package
- `.ops.project/` is the project memory and generated runtime state
- `ops install` installs the universal command once per machine
- `ops setup` initializes or refreshes each project
- runtime commands consume discovered/configured project state instead of
  hard-coded project scripts

Ops is being migrated away from project-specific shell scripts and toward a
generic discovery, setup, run-plan, and execution model.

## Contributing

To change the ops package (commands, discovery, stacks, setup modules), see:

- [CONTRIBUTING.md](CONTRIBUTING.md) — contributor entry point and where-to-change table
- [docs/README.md](docs/README.md) — full documentation index (commands, libraries, stacks, probes)

## Current State

Ops currently supports:

- global `ops` launcher install, doctor, repair, update, and uninstall
- installed package version markers and `ops install update`
- project setup discovery with `.ops.project` materialization
- guided `ops setup` flow when run in an interactive terminal
- modular setup commands for project base, services, dependencies, and CI
- discovery-backed service config for Django, Go, Node, and Phoenix-style apps
- process-group support for Go services with multiple `cmd/*` binaries
- config-first runtime reads from `.ops.project/config`, with `.ops.yaml`
  available only as an explicit compatibility import/export format
- real-time foreground log streaming for service starts
- background service logs and PID files under `.ops.project`
- run-plan inspection before execution
- dependency preview/interview and storage in project config
- local-first CI/server metadata and secrets setup
- focused credential checks for Docker, SSH deploy, and optional GitHub bridge
- simple SSH server connection checks from local config/env
- native basic container build/push and remote compose deploy commands
- optional GitHub Actions secret guidance
- WSL/Windows binary path support for cross-OS execution

The system is usable, but still evolving. `.ops.project/config` is the primary
project state. `.ops.yaml` is optional compatibility I/O for projects or tools
that still need a YAML representation.

## Boundaries

| Path | Owner | Purpose |
| --- | --- | --- |
| `.ops/` | ops package | Commands, libraries, stack strategies, probes, schemas, docs |
| `.ops.project/` | project-local generated state | Config, discovery cache, run plans, logs, PID files, backups, secrets |
| `.ops.yaml` | optional compatibility file | Explicit export/import representation of project config |
| `ops.sh` | repo entrypoint | Runs the local `.ops` package from this repository |

Do not put project-specific values into package files under `.ops/`.

## Install Vs Setup

`install` and `setup` are intentionally separate.

### Install

`ops install` is a one-time, system-level operation. It installs a universal
Bash `ops` command so ops can be called from any repository.

```bash
./ops.sh install
./ops.sh install doctor
./ops.sh install repair
./ops.sh install update
./ops.sh install uninstall
```

When working from the `.ops` package checkout itself, use its package-local
bootstrap first, then use the generated project launcher:

```bash
cd .ops
bash setup
cd ..
./ops.sh install
```

If `.ops` is embedded in a project, the package bootstrap creates the
project-level `ops.sh` without running project setup:

```bash
cd path/to/project/.ops
bash setup
cd ..
./ops.sh setup --dry-run
```

The installed launcher walks upward from the current directory looking for a
project-local `.ops/core/main.sh`. If it finds one, it runs that project copy.
Otherwise it runs the packaged ops core against the current directory.

Install does not initialize a project.

### Setup

`ops setup` is the project initializer.

Bare `ops setup` starts a guided setup sequence when run in a terminal, similar
to modern JavaScript framework initializers. In non-interactive shells it keeps
preview behavior so scripts and CI do not hang.

```bash
ops setup
ops setup --dry-run
ops setup --interactive --apply
ops setup all --apply
```

Setup can also run individual modules:

```bash
ops setup project --apply
ops setup services --apply
ops setup dependencies --interactive --apply
ops setup run-plans --apply
ops setup ci --interactive --apply
```

Module roles:

- `project`: creates the base `.ops.project` structure
- `services`: discovers service candidates and applies runtime service config
- `dependencies`: previews or interviews service dependency decisions
- `run-plans`: regenerates run-plan JSON artifacts from current config
- `ci`: creates local CI/server config and local secrets template
- `all`: full discovery/config/services/dependencies setup path

When applied, the project module also creates a missing root `ops.sh` launcher
without overwriting an existing file.

`ops setup init` remains available for the older detailed setup/profile
interview path.

## Project Memory

`.ops.project/` is the local project memory. It is generated or updated by
setup and runtime commands.

Current shape:

```text
.ops.project/
  .gitignore
  .history/
  config/
    project.json
    services.json
    settings.json
    profiles.json
    decisions.json
    ci.json
  generated/
    discovery.json
    setup.json
    project_structure.json
    project_values.json
    run-plans/
  logs/
  profiles/
  run/
  secrets/
    ci.env
```

Private/local state belongs here:

- logs: `.ops.project/logs/`
- PID files: `.ops.project/run/`
- generated discovery and setup facts: `.ops.project/generated/`
- local config memory: `.ops.project/config/`
- local secrets/env values: `.ops.project/secrets/`
- backups: `.ops.project/.history/`

Secrets and rebuildable runtime artifacts should not be committed.
`.ops.project/.gitignore` ignores secrets, logs, run state, generated outputs,
and local backup history while leaving project config and profiles reviewable.

## Configuration Direction

Runtime reads prefer `.ops.project/config`. `.ops.yaml` is read only as a
compatibility fallback when project config has not been materialized yet, or by
explicit import/export commands.

The desired direction is:

1. Discovery scans the workspace.
2. Setup resolves uncertain values through defaults or interactive prompts.
3. Confirmed decisions are stored in `.ops.project/config`.
4. Runtime commands read project config and generated run plans.
5. `.ops.yaml` remains optional compatibility import/export.

This lets `.ops/` stay package-owned and reusable across projects.

## Commands

### Validate

```bash
ops validate --plain
```

Validation checks project config directly when `.ops.project/config` exists.
If only `.ops.yaml` exists, validation uses it as the compatibility source.

### Doctor

```bash
ops doctor
ops doctor boundaries
ops install doctor
ops setup doctor --profile=local
ops ci doctor
```

Doctor commands check package health, installed launcher health, setup/profile
health, local CI/server metadata, expected tools, SSH key paths, and workflow
file references.

### Show

```bash
ops show start <service_id>
```

Show prints the execution plan before running it, including the config source,
selected runner, stack dispatcher, command candidates, runtime paths, build
outputs, process groups, env context, logs, and PID paths.

### Start, Stop, Logs

```bash
ops start <service_id>
ops start <service_id> --dry-run
ops start <service_id> --background
ops stop <service_id>
ops logs <service_id>
ops logs <service_id> --follow
```

Foreground starts stream service output in real time. Background starts write
logs and PID files under `.ops.project`.

### CI And Server Config

CI support is local-first. GitHub Actions is optional.

```bash
ops ci setup --interactive --apply
ops ssh setup --interactive --apply
ops ssh --interactive --apply
ops ci env --apply
ops ci show
ops ci doctor
ops ci credentials
ops credentials
ops ci connect
ops ssh
ops ci secrets
ops ci ssh-key --apply
```

CI/server metadata is stored in:

```text
.ops.project/config/ci.json
```

Local secrets can live in:

```text
.ops.project/secrets/ci.env
```

This supports a workflow where deployment secrets stay in your own env/config,
and ops connects to your server over SSH. GitHub Actions can still be used as a
bridge, but it is not the foundation of the system.

For the quickest connection smoke test, use:

```bash
ops ssh
ops ssh setup --interactive --apply
ops ssh --interactive --apply
ops ssh --apply
ops ssh --apply --command "hostname && whoami && pwd"
```

Use `ops ssh setup --interactive --apply` to save connection values without
opening a remote SSH session. Without `--apply`, ops prints the exact SSH
command it would run.

For credential readiness, use:

```bash
ops credentials
ops ci credentials
```

This checks local env/config presence, Docker username/password env values,
Docker auth/helper config, deploy SSH key presence, and optional GitHub bridge
readiness without printing secret values.

## Action Resolution

For `ops run <action> <service>`, ops resolves behavior through:

1. project config and generated run-plan state
2. service-specific overrides under `.ops/commands/<service>/`
3. global command overrides under `.ops/commands/`
4. setup-derived service commands
5. stack strategies under `.ops/core/stacks/`
6. explicit configured actions
7. legacy bridge behavior where still needed

Use `ops show <action> <service>` whenever behavior is unclear.

## Cross-OS Direction

Ops is designed to work across Linux, macOS, WSL, and Windows-adjacent
toolchains.

Current cross-OS work includes:

- WSL detection
- Windows executable discovery from WSL
- Windows path translation through `wslpath`
- wrapper/shim support for binaries discovered across shells
- Go build/run handling that can use project config and generated outputs

The direction is to keep cross-shell behavior in generic ops libraries and
stack strategies, not in project-specific command scripts.

## Legacy Compatibility

Legacy scripts can still be reached through:

```bash
./ops.sh legacy ...
```

Compatibility wrappers also exist for older `bootstrap`, `init`, and `update`
flows, but the preferred path is now:

```bash
ops setup
ops show start <service>
ops start <service>
```

## Useful Checks

```bash
ops install doctor
ops setup --dry-run
ops setup project
ops setup services
ops setup dependencies
ops setup ci
ops ci doctor
ops cleanup
ops cleanup images --repository=example/app --min-version=1.2.3
ops cleanup generated
ops backup create --label before-change
ops backup list
ops backup prune --keep 20
ops package status
ops monitor status
ops monitor test --strict
ops monitor credentials
ops monitor setup --postgres --redis --apply
ops monitor postgres info
ops monitor postgres databases
ops monitor postgres users
ops build backend --dry-run
ops deploy backend --dry-run
ops build --service <service_id> --dry-run
ops deploy --service <service_id> --dry-run
ops validate --plain
ops show start <service_id>
ops start <service_id> --dry-run
```

## Roadmap

Near-term direction:

- continue hardening `.ops.project/config` as the primary source for project facts
- keep `.ops.yaml` limited to optional export/import compatibility
- improve the guided setup wizard with better module summaries
- improve dependency graph interviews and persistence
- expand CI/server setup around SSH deploy workflows
- continue removing project-specific command assumptions
- make workspace detection more portable and less dependent on guide files
- strengthen cross-OS shell compatibility
- improve installed package update ergonomics and release/version reporting

The guiding principle: `.ops` should remain reusable package code. Project
facts should be discovered, confirmed, and stored outside the package.
