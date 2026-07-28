# ship command

## Purpose

`ops ship` is the unified continuous-delivery surface. A pipeline can combine
container builds, artifact publication, file synchronization, Git checkout,
deployment activation, custom scripts, and verification without exposing each
mechanism as a separate top-level command.

The lifecycle vocabulary is:

```text
build -> publish -> transfer -> deploy -> verify
```

Drivers may use only the stages they need. For example, `files.sync` starts at
`transfer`, while `docker.compose` normally uses `build`, `publish`, and
`deploy`.

## Current implementation status

The first implementation is deliberately planning-only. It validates
`.ops.project/config/shipping.json` and produces deterministic human-readable
or JSON plans. It does not execute shipping actions yet.

```bash
ops ship production --dry-run
ops ship production --json
ops ship production --job=homepage --dry-run
ops ship production --no-build --no-push --dry-run
ops ship production --only=transfer --dry-run
```

Calling `ops ship` without `--dry-run` or `--json` exits with status 2 until
execution receipts, resume behavior, verification, and rollback are added.
This prevents a planning-only release from being mistaken for a deployment.

## Configuration

Shipping configuration lives at:

```text
.ops.project/config/shipping.json
```

Create or review it through setup:

```bash
ops setup shipping
ops setup shipping --interactive --apply
```

It is validated against the structural contract in
`schemas/shipping.schema.json`. The supported planning drivers are:

| Driver | Required configuration | Planned behavior |
| --- | --- | --- |
| `docker.compose` | `compose_files` | build, publish, optional transfer, deploy, optional verify |
| `files.sync` | `source`, `destination` | transfer, optional activate/deploy and verify |
| `git.checkout` | `repository`, `destination` | checkout/fetch, optional build, deploy, and verify |
| `script` | `stages` | explicitly configured lifecycle actions |

Project-specific values belong in the project configuration. Driver behavior
and validation remain package-owned under `.ops/`.

## Stage controls

- `--no-build`
- `--no-publish` or Docker-oriented alias `--no-push`
- `--no-transfer` or compatibility alias `--no-sync`
- `--no-deploy`
- `--no-verify`
- `--only=build|publish|transfer|deploy|verify`

The plan records disabled actions and their skip reason instead of silently
discarding them.

## Source files

- `core/commands/ship.sh`
- `core/lib/shipping.sh`
- `schemas/shipping.schema.json`
- `tests/smoke/shipping.bash`

## Next execution slice

Execution should consume the exact JSON plan produced here. It must add:

1. target and credential resolution after planning;
2. driver-specific execution without shell `eval`;
3. run receipts under `.ops.project/.history/shipping/`;
4. dependency ordering, resume, verification, and rollback hooks;
5. compatibility adapters for existing project shipping scripts.
