# Schemas and templates

## Purpose

JSON Schema and default templates for setup-generated config fragments.

## Source files

```text
.ops/schemas/
  profile.schema.json
  setup.schema.json
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

Setup and validate paths use these as reference shapes when materializing `.ops.project/config/` and validating user-facing JSON.

## Extension points

When adding config keys:

1. Update the relevant schema under `schemas/`.
2. Update default template under `templates/` if applicable.
3. Document fields in [reference/config-files.md](../reference/config-files.md).

## See also

- [../commands/validate.md](../commands/validate.md)
