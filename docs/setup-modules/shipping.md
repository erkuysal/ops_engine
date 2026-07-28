# Shipping setup module

## Purpose

`ops setup shipping` owns creation and refresh of
`.ops.project/config/shipping.json`. Shipping configuration is project memory;
it must not be hard-coded into the reusable `.ops` package or created as an
undocumented manual prerequisite.

## Commands

```bash
ops setup shipping
ops setup shipping --json
ops setup shipping --refresh
ops setup shipping --interactive
ops setup shipping --interactive --apply
ops setup shipping --refresh --apply
```

The command is preview-only unless `--apply` is explicit.

## Inference

Setup searches for standard Compose filenames and manifests under
`deployment/compose/`. It prefers these conventional application manifests:

1. `deployment/compose/app/production.yml`
2. `docker-compose.yml`
3. `deployment/compose/app/staging.yml`
4. `docker-compose.staging.yml`

If those conventions are absent, setup proposes a local pipeline from the
first discovered Compose file. It does not invent file-transfer, Git, or
custom-script behavior because those actions cannot be inferred safely.

## Interactive decisions

`--interactive` can add jobs using:

- `docker.compose`
- `files.sync`
- `git.checkout`
- `script`

The setup flow asks only for driver-specific values. Custom commands are stored
as argument arrays, not shell strings.

## Preservation

When a shipping config already exists, setup treats it as reviewed project
state and preserves it. Use `--refresh` to explicitly discard that proposal and
re-run inference. Applying over an existing file stores a timestamped copy
under `.ops.project/.history/`.

## Source files

- `core/commands/setup-shipping.sh`
- `core/commands/setup.sh`
- `core/lib/shipping.sh`
- `schemas/shipping.schema.json`
