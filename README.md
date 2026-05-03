# Ops Package

**Ops** is a reusable, framework-agnostic **development orchestration system** for multi-service projects. It provides:

- 🎯 **Unified command interface** for starting, stopping, and managing services
- 🏗️ **Stack-based dispatch** with auto-detection of Go, Python, Node.js, Elixir, and other runtimes
- 🔧 **Service manifests** (`.ops.yaml`) for declaring projects, runtimes, ports, env files, and profiles
- 📊 **Real-time log streaming** with stdbuf integration for immediate feedback
- 🌍 **Multi-environment support** (local, staging, production, remote/VPS)
- 🔄 **Extensible architecture** with local/global command overrides and probe-based discovery

`.ops/` contains package code, stack strategies, schemas, templates, and documentation only. Active project-specific values belong in `.ops.yaml` and `.ops.project/`.

Discovery inside `.ops/` is probe-based: small stack probe scripts live under `.ops/core/probes/` and are loaded by the engine when scanning the workspace.

## Current State

**Phase:** Core functionality implemented. Stable for multi-service orchestration with real-time log streaming.

**What works:**
- ✅ Multi-stack service orchestration (Django, Phoenix, Go, Node.js)
- ✅ Real-time foreground/background execution with log streaming
- ✅ Cross-shell binary support (Windows binaries accessible from WSL)
- ✅ Service manifests and stack-based dispatch
- ✅ Local/global command overrides
- ✅ Profile-based environment management (local/staging/production)
- ✅ Probe-based runtime auto-detection

**Known limitations:**
- Docker Compose integration is manual (compose files must be configured in profiles)
- No built-in service dependency orchestration (must configure manually in `.ops.yaml`)
- Windows binary path translation requires explicit stack handler enhancement (see [Cross-Platform issue](ISSUES/1_CROSS_PLATFORM.md))

## Upcoming Features

### Docker Integration (Phase 2)
- ✨ Auto-probe Docker Compose files under `docker-compose.*.yml`
- ✨ Service discovery from docker-compose.yml stack definitions
- ✨ One-command Docker network and volume setup
- ✨ Health check verification via Docker container inspect

### Service Dependency Resolution (Phase 2)
- ✨ Automatic dependency ordering (start dependencies before service)
- ✨ Health check assertions before marking service as ready
- ✨ Parallel service startup with proper sequencing

### Enhanced Cross-Platform Support (Phase 2)
- ✨ Stack-level Windows binary handling (see [1_CROSS_PLATFORM.md](ISSUES/1_CROSS_PLATFORM.md))
- ✨ ARM/x86 cross-compilation detection
- ✨ WSL/Windows path translation transparency

### CI/CD Templating (Phase 3)
- ✨ GitHub Actions/GitLab CI/Jenkins workflow generators
- ✨ Environment variable materialization for CI contexts
- ✨ Automated testing and linting hooks

### Remote/VPS Deployment (Phase 3)
- ✨ SSH-based remote service management
- ✨ Remote log tailing and monitoring
- ✨ Certificate and secrets management

## Dependencies

### Required
- **bash** ≥ 4.0 — Core orchestration language
- **jq** — YAML/JSON manifest parsing
- **wslpath** (WSL only) — Path translation for cross-platform execution

### Optional (Stack-Specific)
| Stack | Required | Optional |
|-------|----------|----------|
| **go** | `go` binary (WSL or Windows) | — |
| **python** | `python`/`conda` | `pip`, `poetry` |
| **node** | `node`, `npm` | `yarn`, `pnpm` |
| **elixir** | `elixir`, `mix` | — |
| **django** | `python`, `manage.py` | `poetry`, `pip` |
| **docker** | `docker`, `docker-compose` | — |
| **postgres** | — | `psql` (for health checks) |
| **redis** | — | `redis-cli` (for health checks) |

### Environment
- **Linux/macOS**: Works natively
- **WSL2 (Windows)**: Fully supported with Windows binary detection
- **Docker**: Works inside containers with proper volume mounting
- **CI/CD**: GitHub Actions, GitLab CI, Jenkins compatible

## Boundaries

| Path | Owner | Purpose |
| --- | --- | --- |
| `.ops/` | ops package | Commands, libraries, stack strategies, schemas, templates, docs |
| `.ops.yaml` | project | Services, settings, setup, profiles, runtimes, ports, remotes |
| `.ops.project/` | generated project state | Logs, PID files, generated materializations, backups |
| `ops.sh` | package entrypoint | Stable command entrypoint into `.ops/core/main.sh` |

Do not put active project values in `.ops/settings.json`, `.ops/setup.json`, or `.ops/profiles/*.json`. Those files may exist from older iterations, but current code reads active values from `.ops.yaml`.

## Current Config Source

The root `.ops.yaml` is the source of truth. It contains:

- `project`: project name and global env files
- `services`: service manifest and stack mapping
- `settings`: ops behavior defaults
- `setup`: project runtime facts
- `profiles`: environment-specific local/staging/production/remote values
- `ci`: CI policy
- `overrides`: reserved override metadata

Example shape:

```yaml
settings:
  run:
    default_mode: foreground
  start:
    mode: foreground
    with_deps: true
    preview:
      enabled: true
      lines: 20
      wait_seconds: 1

setup:
  default_profile: ""
  scaffold:
    type: ""
    package_manager: ""
    template: ""
  runtimes:
    python:
      manager: ""
      env: ""
      fallbacks: []
  services:
    backend:
      runtime: ""
      port: 0
      command: ""
      env_files: []

profiles:
  local:
    docker:
      network: ""
      compose_files: []
    healthchecks: {}
```

## Generated State

`.ops.project/` is created by `ops setup --apply` and used for generated state:

```text
.ops.project/
  logs/
  run/
  generated/
  profiles/
  .history/
```

Runtime files:

- Logs: `.ops.project/logs/<service>.log`
- PID files: `.ops.project/run/<service>.pid`
- Setup materializations: `.ops.project/generated/`
- Backups: `.ops.project/.history/`

## Commands

### Install

Install or repair the local ops package/state boundary:

```bash
./ops.sh install
./ops.sh install --repair
./ops.sh install --dry-run
./ops.sh install doctor
```

`install` verifies package files under `.ops/` and command scaffolding. It does not create project runtime state.

### Setup

Generate, apply, inspect, and validate project setup values in `.ops.yaml`:

```bash
./ops.sh setup --profile=local --dry-run
./ops.sh setup --profile=local --apply
./ops.sh setup init --profile=local --apply
./ops.sh setup --interactive --profile=local --apply
./ops.sh setup show --profile=local
./ops.sh setup doctor --profile=local
./ops.sh setup doctor --profile=production
```

`setup --apply` writes empty/project-neutral setup scaffolding by default. `setup init` and `setup --interactive` prompt for scaffold type, package manager, runtime, service commands, ports, env files, remote/VPS values, Docker values, certificates, and healthchecks before writing `.ops.yaml`.

`setup --apply` updates `.ops.yaml`, creates `.ops.project/` if needed, materializes derived files there, and refreshes `scripts/project_structure.json` plus `project_metadata` in `scripts/project_values.json` from the manifest.

### Validate

Validate root config and related package expectations:

```bash
./ops.sh validate --plain
```

Validation covers:

- `.ops.yaml` syntax
- required manifest sections
- service IDs, stacks, env policy, dependencies
- service paths and env files
- local override scripts
- `.ops.yaml` `settings`, `setup`, and `profiles`
- probe-based workspace discovery (`.ops/core/probes/*.sh`)
- existence of `.ops.project/`

### Doctor

Check package and project health:

```bash
./ops.sh doctor
```

Doctor verifies the `.ops/` package files, `.ops.project/` state directory, root `.ops.yaml`, and required tools.

### Show

Inspect the exact execution plan:

```bash
./ops.sh show start backend
```

Output includes:

- selected service and stack
- active root config source
- active profile
- service command
- service port
- runtime
- selected runner
- env files
- masked env context
- log/PID paths under `.ops.project/`

### Start, Stop, Logs

```bash
./ops.sh start backend
./ops.sh start backend --background
./ops.sh start backend --foreground
./ops.sh start backend --dry-run
./ops.sh stop backend
./ops.sh logs backend
./ops.sh logs backend --follow
```

Foreground/background defaults are read from `.ops.yaml -> settings`.

Background starts write logs/PIDs to `.ops.project/` and print a startup preview.

## Action Resolution

For `./ops.sh run <action> <service>`, resolution order is:

1. Service override: `.ops/commands/<service>/<action>.sh`
2. Global override: `.ops/commands/<action>.sh`
3. Setup command: `.ops.yaml -> setup.services.<service>.command` for `start`
4. Stack strategy: `.ops/core/stacks/<stack>.sh`
5. Explicit manifest action: `.ops.yaml -> services[].actions.<action>`
6. Legacy bridge: `scripts/commands.sh`

Use `show` whenever behavior is unclear:

```bash
./ops.sh show start backend
```

## Profiles

Profiles live under `.ops.yaml -> profiles`.

Typical profiles:

- `local`
- `staging`
- `production`
- `remote`

Remote/VPS profiles can define:

- `remote.host`
- `remote.user`
- `remote.path`
- `remote.ssh_key_path`
- `docker.network`
- `docker.compose_files`
- `healthchecks`
- `certificates`

Secrets should not be stored in profiles. Store secrets in env files, CI secrets, server environment, or secret managers.

## Package Templates And Schemas

`.ops/templates/` and `.ops/schemas/` are package-owned. They are generic examples and validation aids, not active project config.

Package templates must stay project-neutral. Project-specific materialized values belong in `.ops.yaml` and `.ops.project/`.

## Migration Note

Older local files may still exist:

- `.ops/settings.json`
- `.ops/setup.json`
- `.ops/profiles/*.json`
- `.ops/logs/`
- `.ops/run/`

They are deprecated as active config/state. Current code reads from `.ops.yaml` and writes runtime state to `.ops.project/`.

Do not delete old files automatically unless explicitly requested. They can be removed or archived after verification.

## Recommended Checks

```bash
./ops.sh install doctor
./ops.sh setup show --profile=local
./ops.sh setup doctor --profile=local
./ops.sh setup doctor --profile=production
./ops.sh validate --plain
./ops.sh show start backend
./ops.sh start backend --dry-run
```

