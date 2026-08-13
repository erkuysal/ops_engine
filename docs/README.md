# Ops package documentation

Contributor and implementation docs for the `.ops` package. For day-to-day usage (install, setup, start services), see [README.md](../README.md).

## Start here

| Doc | Audience |
| --- | --- |
| [architecture.md](architecture.md) | How commands, discovery, config, and runtime fit together |
| [boundaries.md](boundaries.md) | What belongs in `.ops/`, `.ops.project/`, and optional YAML exports |
| [development.md](development.md) | Local workflow, env vars, debugging, smoke checks |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Contributor entry point and decision table |

## Setup modules

| Doc | CLI |
| --- | --- |
| [setup-modules/project.md](setup-modules/project.md) | `ops setup project` |
| [setup-modules/services.md](setup-modules/services.md) | `ops setup services` |
| [setup-modules/dependencies.md](setup-modules/dependencies.md) | `ops setup dependencies` |
| [setup-modules/run-plans.md](setup-modules/run-plans.md) | `ops setup run-plans` |
| [setup-modules/ci.md](setup-modules/ci.md) | `ops setup ci` |
| [setup-modules/shipping.md](setup-modules/shipping.md) | `ops setup shipping` |
| [setup-modules/all-and-wizard.md](setup-modules/all-and-wizard.md) | `ops setup`, `ops setup all`, wizard |

## Commands

| Doc | Source |
| --- | --- |
| [commands/install.md](commands/install.md) | `core/commands/install.sh` |
| [commands/global.md](commands/global.md) | `core/commands/global.sh`, `core/lib/global_profiles.sh` |
| [commands/setup.md](commands/setup.md) | `core/commands/setup.sh` |
| [commands/run.md](commands/run.md) | `core/commands/run.sh` |
| [commands/show.md](commands/show.md) | `core/commands/show.sh` |
| [commands/start.md](commands/start.md) | `core/commands/start.sh` |
| [commands/stop.md](commands/stop.md) | `core/commands/stop.sh` |
| [commands/status.md](commands/status.md) | `core/commands/status.sh` |
| [commands/logs.md](commands/logs.md) | `core/commands/logs.sh` |
| [commands/cleanup.md](commands/cleanup.md) | `core/commands/cleanup.sh` |
| [commands/backup.md](commands/backup.md) | `core/commands/backup.sh`, `core/commands/rollback.sh` |
| [commands/package.md](commands/package.md) | `core/commands/package.sh` |
| [commands/monitor.md](commands/monitor.md) | `core/commands/monitor.sh` |
| [commands/ship.md](commands/ship.md) | `core/commands/ship.sh`, `core/lib/shipping.sh` |
| [commands/build.md](commands/build.md) | `core/commands/build.sh` |
| [commands/deploy.md](commands/deploy.md) | `core/commands/deploy.sh` |
| [commands/ci.md](commands/ci.md) | `core/commands/ci.sh` |
| [commands/validate.md](commands/validate.md) | `core/commands/validate.sh` |
| [commands/doctor.md](commands/doctor.md) | `core/commands/doctor.sh` |
| [commands/env.md](commands/env.md) | `core/commands/env.sh` |
| [commands/init.md](commands/init.md) | `core/commands/init.sh` |
| [commands/bootstrap.md](commands/bootstrap.md) | `core/commands/bootstrap.sh` |
| [commands/update.md](commands/update.md) | `core/commands/update.sh` |

## Core libraries

| Doc | Source |
| --- | --- |
| [core/init.md](core/init.md) | `core/lib/init.sh` |
| [core/discovery.md](core/discovery.md) | `core/lib/discovery.sh`, `detect.sh` |
| [core/setup-lib.md](core/setup-lib.md) | `core/lib/setup.sh` |
| [core/manifest.md](core/manifest.md) | `core/lib/manifest.sh` |
| [core/run-plan.md](core/run-plan.md) | `core/lib/run_plan.sh` |
| [core/settings.md](core/settings.md) | `core/lib/settings.sh` |
| [core/env.md](core/env.md) | `core/lib/env.sh` |
| [core/env-materialize.md](core/env-materialize.md) | `core/lib/env_materialize.sh` |
| [core/graph.md](core/graph.md) | `core/lib/graph.sh` |
| [core/interactive.md](core/interactive.md) | `core/lib/interactive.sh` |
| [core/cross-shell.md](core/cross-shell.md) | `core/lib/cross_shell.sh` |
| [core/preflight.md](core/preflight.md) | `core/lib/preflight.sh` |
| [core/backup.md](core/backup.md) | `core/lib/backup.sh` |
| [core/logger.md](core/logger.md) | `core/lib/logger.sh` |
| [core/probes.md](core/probes.md) | `core/probes/` overview |
| [core/stacks.md](core/stacks.md) | `core/stacks/` overview |

## Stacks

| Doc | Source |
| --- | --- |
| [stacks/django.md](stacks/django.md) | `core/stacks/django.sh` |
| [stacks/go.md](stacks/go.md) | `core/stacks/go.sh` |
| [stacks/node.md](stacks/node.md) | `core/stacks/node.sh` |
| [stacks/elixir-phoenix.md](stacks/elixir-phoenix.md) | `core/stacks/elixir-phoenix.sh` |
| [stacks/docker.md](stacks/docker.md) | `core/stacks/docker.sh` |
| [stacks/custom.md](stacks/custom.md) | `core/stacks/custom.sh` |

## Probes

| Doc | Source |
| --- | --- |
| [probes/django.md](probes/django.md) | `core/probes/django.sh` |
| [probes/go.md](probes/go.md) | `core/probes/go.sh` |
| [probes/node.md](probes/node.md) | `core/probes/node.sh` |
| [probes/elixir-phoenix.md](probes/elixir-phoenix.md) | `core/probes/elixir-phoenix.sh` |
| [probes/docker.md](probes/docker.md) | `core/probes/docker.sh` |

## Extending

| Doc | Topic |
| --- | --- |
| [extending/new-probe.md](extending/new-probe.md) | Add a discovery probe |
| [extending/new-stack.md](extending/new-stack.md) | Add a runtime stack |
| [extending/new-setup-module.md](extending/new-setup-module.md) | Add a setup module |
| [extending/schemas-and-templates.md](extending/schemas-and-templates.md) | JSON schemas and templates |

## Reference

| Doc | Topic |
| --- | --- |
| [reference/action-resolution.md](reference/action-resolution.md) | How `ops run` picks a runner |
| [reference/config-files.md](reference/config-files.md) | `.ops.project` layout |
| [reference/json-output.md](reference/json-output.md) | The shared `--json` envelope and which commands support it |
| [reference/legacy.md](reference/legacy.md) | Legacy bridge and `./ops.sh legacy` |

## Process and vision (outside `docs/`)

- [PROJECT_AIMS.md](../PROJECT_AIMS.md) — target architecture and roadmap
- [ONGOING.md](../ONGOING.md) — active implementation checklist
- [core/MIGRATION.md](../core/MIGRATION.md) — legacy command mapping
- [ISSUES/](../ISSUES/) — design notes (e.g. cross-platform)
