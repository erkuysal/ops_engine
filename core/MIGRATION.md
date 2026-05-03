# Legacy Compatibility Matrix

This document maps legacy `./ops.sh` commands to the new Orchestrator equivalents (`./ops.sh experimental ...`), detailing whether the new command runs natively or bridges backwards to the old scripts.

The new discovery model is probe-based: stack fingerprints are implemented as small scripts under `.ops/core/probes/`, and `setup --apply` regenerates the project reference JSON files from the manifest.

## Core Commands

| Legacy Command | Orchestrator Equivalent | Execution Path |
| --- | --- | --- |
| `./ops.sh dev start <svc>` | `ops run start <svc>` | **Native** (`.ops-core/stacks/*.sh`) |
| `./ops.sh dev stop <svc>` | `ops run stop <svc>` | **Native** (`.ops-core/stacks/*.sh`) |
| `./ops.sh dev logs <svc>` | `ops run logs <svc>` | **Native** (`.ops-core/stacks/*.sh`) |
| `./ops.sh dev status <svc>` | `ops run status <svc>` | **Native** (`.ops-core/stacks/*.sh`) |

## CI/CD Pipeline Commands

These commands use the **Compatibility Bridge** (Phase 8). The orchestrator routes them securely via `env_exec` into the legacy `.scripts/` folder, injecting `--services <svc>` where appropriate.

| Legacy Command | Orchestrator Equivalent | Execution Path (Bridged) |
| --- | --- | --- |
| `./ops.sh ship build --services <svc>` | `ops run build <svc>` | Bridged ➔ `.scripts/deploy/build.sh` |
| `./ops.sh ship deploy --services <svc>` | `ops run deploy <svc>` | Bridged ➔ `.scripts/deploy/deploy.sh` |
| `./ops.sh ship staging --services <svc>` | `ops run staging <svc>` | Bridged ➔ `.scripts/deploy/deploy-staging.sh` |
| `./ops.sh ship release --services <svc>` | `ops run release <svc>` | Bridged ➔ `.scripts/deploy/release.sh` |
| `./ops.sh ship update --services <svc>` | `ops run update <svc>` | Bridged ➔ `.scripts/deploy/update.sh` |
| `./ops.sh ship publish --services <svc>` | `ops run publish <svc>` | Bridged ➔ `.scripts/deploy/publish.sh` |

## How the Bridge Works
When you run `ops run <action> <svc>`, the orchestrator looks for the action in the native Stack Strategy (e.g., `django.sh`). 

If it's **Not Implemented**, it falls back to checking your `.ops.yaml` for an `EXPLICIT_CMD`.

If that's empty, it falls back to the **Legacy Registry** (`scripts/commands.sh`), finds the legacy script path, and executes it from the project root while maintaining the sandboxed environment context (`OPS_SERVICE_ID`, `OPS_PROJECT_ROOT`, etc.).
