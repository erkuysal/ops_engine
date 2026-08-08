# .ops.yaml retirement tasklist

Goal: make `.ops.project/config` the primary project state everywhere, and reduce
`.ops.yaml` to an explicit import/export compatibility format.

This is a staged cleanup. Do not remove YAML support in one pass; first remove
runtime dependence, then clean setup/write paths, then update docs and messages.

## Principles

- Runtime commands should read `.ops.project/config` first and should not require
  `.ops.yaml` when config exists.
- Mutating project setup flows should write `.ops.project/config` by default.
- `.ops.yaml` writes should happen only through explicit export/sync commands.
- Import from `.ops.yaml` remains supported as a compatibility migration path.
- User-facing messages should say "project config" unless the action is
  specifically about YAML import/export.

## Slice 1: Runtime read-path audit

- [x] Replace manifest-only global env reads in `core/lib/env.sh` with
  config-first project env reads.
- [x] Replace `manifest_get_field '.project.global_env_files...'` call sites
  with a shared config-first helper.
- [x] Audit `core/lib/run_plan.sh` fallback reads for build outputs and runner
  metadata; prefer `services.json` whenever present.
- [x] Audit `core/lib/setup.sh` fallback reads that call `yq` directly; keep
  fallback only for no-config projects.
- [x] Add smoke coverage for config-only env context without `.ops.yaml`.

## Slice 2: Mutating write-path cleanup

- [x] Ensure interactive Django Conda persistence writes `services.json`,
  `settings.json`, and generated setup state when project config exists.
- [x] Audit all `yq e -i` writes to `${OPS_MANIFEST}` and gate them behind
  explicit YAML export/import flows or manifest-only fallback.
- [x] Verify `bootstrap`, `init`, and `update` wrappers do not create or mutate
  `.ops.yaml` unless explicitly requested.
- [x] Keep `ops setup export-yaml --apply` as the only normal YAML write path.
- [x] Keep `ops setup import-yaml --apply` as the explicit YAML-to-config path.

## Slice 3: Validation without YAML temp dependence

- [x] Review `manifest_prepare_validation_source`; decide whether validation can
  run directly from JSON config instead of producing a temporary YAML manifest.
- [x] Rename validation messages from "manifest" to "project config" when config
  is the source.
- [x] Keep YAML syntax validation only when `.ops.yaml` is the selected source.
- [x] Add tests for `ops validate --plain` in config-only mode with no YAML file.

## Slice 4: Setup command language and previews

- [x] Rename "Proposed .ops.yaml services from discovery" to "Proposed project
  config services from discovery".
- [x] Rename "Proposed .ops.yaml setup from discovery" to "Proposed setup config
  from discovery".
- [x] Update setup info/warning text so YAML is mentioned only as optional
  export/import compatibility.
- [x] Update `ops setup show` labels from "Root config" / compatibility manifest
  to clearer config-first wording.
- [x] Add `--profile NAME` space-form support while touching setup parsing.

## Slice 5: Doctor and status wording

- [x] Update `ops doctor` to treat missing `.ops.yaml` as normal when
  `.ops.project/config` exists.
- [x] Update doctor messages that still suggest legacy init commands.
- [x] Update status/show/run-plan labels that call YAML the main config source.
- [x] Add a doctor check that reports YAML/config sync drift only when both
  formats exist.

## Slice 6: Documentation cleanup

- [x] Update `README.md` to describe `.ops.yaml` as optional export/import only.
- [x] Update `docs/architecture.md` setup flow: config-first, YAML optional.
- [x] Update `docs/boundaries.md` ownership table and generated-vs-hand-edited
  section.
- [x] Update `docs/reference/config-files.md` to put YAML under compatibility.
- [x] Update command docs that still say "reads `.ops.yaml`" when config-first
  is true.
- [x] Update `PROJECT_AIMS.md` and `ONGOING.md` to remove completed historical
  gaps that are now stale.

## Slice 7: Compatibility boundary

- [x] Decide if `manifest.sh` should be renamed or wrapped by a config-neutral
  API name in a future major cleanup.
- [x] Keep legacy `manifest_*` helpers for now, but ensure new code uses
  config-first helpers.
- [x] Add contributor note: new runtime code must not call `require_manifest`
  unless the command is explicitly YAML import/export.

## Slice 8: Neutral runtime vocabulary

- [x] Make `project_*` accessors the primary implementations and retain
  `manifest_*` names only as compatibility wrappers.
- [x] Migrate runtime commands, status, graph, environment, runner, and
  container pipeline code to `project_*` accessors.
- [x] Remove direct YAML reads from run-plan and Go stack helpers through a
  structured `project_get_service_json_field` accessor.
- [x] Keep direct `yq` use only where YAML itself is the explicit input/output,
  including validation, drift reporting, import/export, setup migration, and
  Docker Compose inspection.
- [x] Add a smoke boundary that rejects legacy accessor calls in migrated
  runtime files.

## Candidate verification commands

```bash
bash tests/run.sh
bash ../ops.sh setup --dry-run
bash ../ops.sh setup --apply
bash ../ops.sh validate --plain
bash ../ops.sh show start backend
bash ../ops.sh start backend --dry-run --no-wait
```

From Windows PowerShell with WSL:

```powershell
wsl bash -lc "cd /path/to/project/.ops && bash tests/run.sh 2>&1 | tee log"
```
