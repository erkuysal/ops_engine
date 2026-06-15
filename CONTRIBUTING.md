# Contributing to Ops

Thank you for contributing to the `.ops` package. This document is the entry point for implementers; operators should start with [README.md](README.md).

## What ops is

Ops is a reusable Bash orchestration package: global `ops install`, per-project `ops setup`, and runtime commands (`start`, `stop`, `run`, `show`, …) that consume `.ops.project` state. See [docs/architecture.md](docs/architecture.md) for the full picture.

## Package boundaries

**Never put project-specific values in package files under `.ops/`.**

Project facts belong in `.ops.project/`. `.ops.yaml` is optional compatibility
import/export only. Details: [docs/boundaries.md](docs/boundaries.md).

For runtime/project reads, prefer config-neutral helpers such as
`project_list_services`, `project_get_service_field`, and
`project_require_config_or_yaml`. Avoid new direct `require_manifest` or `yq`
reads unless the command is explicitly handling YAML import/export.

## Repository layout

| Path | Purpose |
| --- | --- |
| `core/main.sh` | CLI router |
| `core/commands/` | Top-level command implementations |
| `core/lib/` | Shared libraries (sourced) |
| `core/stacks/` | Stack runtime strategies |
| `core/probes/` | Discovery fingerprint scripts |
| `schemas/` | JSON Schema for config shapes |
| `templates/` | Default JSON templates |
| `tests/` | Smoke tests and stack fixtures |
| `docs/` | Contributor documentation (module docs) |

## Prerequisites

- Bash 4+, `jq`, `yq`
- Tools for stacks you are changing (Go, Node, Python, etc.)
- A consuming repo with `ops.sh` for integration testing

## Development workflow

1. Clone or work in the `.ops` repository.
2. Run package smoke tests: `bash tests/run.sh`.
3. Test from a consuming repo when needed: `./ops.sh <command>`.
4. Use `OPS_DEBUG=true` and `--dry-run` before `--apply`.
5. Update docs under `docs/` for any behavior you change.
6. Run smoke checks from [docs/development.md](docs/development.md).

## Where to change what

| You want to… | Start here | Documentation |
| --- | --- | --- |
| Add or fix a CLI command | `core/commands/<name>.sh`, register in `core/main.sh` | [docs/commands/](docs/commands/) |
| Change setup behavior | `core/commands/setup.sh`, `core/lib/setup.sh` | [docs/setup-modules/](docs/setup-modules/) |
| Change discovery | `core/lib/discovery.sh`, `core/lib/detect.sh`, `core/probes/` | [docs/core/discovery.md](docs/core/discovery.md), [docs/core/probes.md](docs/core/probes.md) |
| Change how a service runs | `core/stacks/<stack>.sh`, `core/lib/run_plan.sh` | [docs/core/stacks.md](docs/core/stacks.md), [docs/core/run-plan.md](docs/core/run-plan.md) |
| Add a stack | New `core/stacks/*.sh`, probe, validate stack list | [docs/extending/new-stack.md](docs/extending/new-stack.md) |
| Add a probe | New `core/probes/*.sh`, wire in discovery | [docs/extending/new-probe.md](docs/extending/new-probe.md) |
| CI / SSH / credentials | `core/commands/ci.sh` | [docs/commands/ci.md](docs/commands/ci.md) |
| JSON config shape | `schemas/`, `templates/` | [docs/extending/schemas-and-templates.md](docs/extending/schemas-and-templates.md) |

Full index: [docs/README.md](docs/README.md).

## Coding conventions

- `set -euo pipefail` in every script
- Double-source guards (`_OPS_*_LOADED`)
- `die` / `ops_error` for failures; no secrets in repo
- `require_within_root` for paths derived from user input
- Match naming and structure of neighboring files

## Testing / verification

| Change type | Minimum checks |
| --- | --- |
| Manifest / validation | `./ops.sh validate --plain` |
| Setup | `./ops.sh setup --dry-run`, module-specific `--apply` on a test project |
| Runtime / stacks | `./ops.sh show start <svc>`, `./ops.sh start <svc> --dry-run` |
| Install | `./ops.sh install doctor` |
| CI | `./ops.sh ci doctor`, `./ops.sh credentials` |

## Related documentation

- [docs/README.md](docs/README.md) — documentation index
- [PROJECT_AIMS.md](PROJECT_AIMS.md) — vision and roadmap
- [ONGOING.md](ONGOING.md) — active work tracker
- [core/MIGRATION.md](core/MIGRATION.md) — legacy command mapping
- [ISSUES/](ISSUES/) — design notes

## Submitting changes

`.ops` is maintained as its own git repository.

- Keep diffs focused; one concern per change when possible.
- Update the relevant `docs/` page(s) in the same change.
- Mention user-visible behavior changes in `ONGOING.md` when appropriate.
- Do not commit `.ops.project/`, secrets, or local test artifacts.
