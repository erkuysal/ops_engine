# setup command

## Purpose

Project initializer: discovery, config materialization, modular setup, and interactive wizard.

## CLI / entrypoints

```bash
ops setup
ops setup all [--apply]
ops setup project|services|dependencies|run-plans|ci [--apply]
ops setup run-plans [--actions=start,status] [--apply]
ops setup export-yaml|import-yaml [--apply]
ops setup discover|apply-services|show|check|doctor
ops setup --check [--json]
ops setup --module=NAME [--apply]
ops setup --dry-run|--interactive|--apply
```

## Source files

- `core/commands/setup.sh`
- Libraries: `discovery.sh`, `setup.sh`, `manifest.sh`

## Module documentation

| Module | Doc |
| --- | --- |
| project | [setup-modules/project.md](../setup-modules/project.md) |
| services | [setup-modules/services.md](../setup-modules/services.md) |
| dependencies | [setup-modules/dependencies.md](../setup-modules/dependencies.md) |
| run-plans | [setup-modules/run-plans.md](../setup-modules/run-plans.md) |
| ci | [setup-modules/ci.md](../setup-modules/ci.md) |
| wizard / all | [setup-modules/all-and-wizard.md](../setup-modules/all-and-wizard.md) |
| export-yaml | [../reference/config-files.md](../reference/config-files.md) |
| import-yaml | [../reference/config-files.md](../reference/config-files.md) |

## Config sync

By default, `ops setup --apply` writes `.ops.project/config` only. Use `--export-yaml --apply` to also write `.ops.yaml`.

When config files already exist, `ops setup --apply` first creates a
`pre-setup` config snapshot under `.ops.project/.history/config/`.

## Profiles and env discovery

Local/dev profiles ignore deployment env files such as `.env.staging`,
`.env.production`, `.staging.env`, and `.production.env` during discovery.
Use an explicit profile to opt in:

```bash
ops setup discover --profile=staging --apply
ops setup --profile=production --apply
```

`ops show` and `ops start` warn when the current config references a deployment
env file that does not match the active setup profile.

```bash
ops setup export-yaml          # preview .ops.yaml from .ops.project/config
ops setup export-yaml --apply
ops setup import-yaml --apply  # materialize config from existing .ops.yaml
```

Implementation: `core/lib/manifest_sync.sh`.

## Testing

```bash
./ops.sh setup --dry-run
./ops.sh setup project --apply
```

## See also

- [../core/discovery.md](../core/discovery.md)
