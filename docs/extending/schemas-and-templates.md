# Schemas and templates

## Purpose

JSON Schema and default templates for setup-generated config fragments.

## Source files

```text
.ops/schemas/
  global-profile.schema.json
  profile.schema.json
  profiles-config.schema.json
  project-config.schema.json
  services-config.schema.json
  shipping.schema.json
  setup.schema.json
  settings-config.schema.json
  settings.schema.json
.ops/templates/
  setup.json
  settings.json
  profiles/local.json
  profiles/staging.json
  profiles/production.json
  profiles/remote.json
```

## Usage

Setup and validate paths use these as reference shapes when materializing
`.ops.project/config/` and validating user-facing JSON. `setup`, `settings`, and
`profile` schemas describe individual fragments. The `*-config` schemas describe
the aggregate files written under `.ops.project/config/`.

Schema versions are stored as integer `1`. Runtime validation continues to read
the legacy string value `"1"` and reports a warning so existing projects can be
regenerated without a breaking migration.

Run the schema contract suite with:

```bash
bash tests/schema/run.sh
```

The suite maps each schema to its templates or representative generated config,
verifies deliberately invalid fixtures are rejected, and checks selected valid
and invalid cases against the dependency-light runtime validator. It requires
`ajv-cli` 5.x (`npm install --global ajv-cli@5.0.0`).

## Extension points

When adding config keys:

1. Update the relevant schema under `schemas/`.
2. Update default template under `templates/` if applicable.
3. Document fields in [reference/config-files.md](../reference/config-files.md).

## See also

- [../commands/validate.md](../commands/validate.md)
