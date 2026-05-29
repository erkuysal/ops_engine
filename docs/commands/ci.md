# ci command

## Purpose

Local-first CI/deploy configuration: server metadata, credential readiness, SSH checks, optional GitHub secret guidance.

## CLI / entrypoints

```bash
ops ci setup [--interactive] [--apply] [--profile NAME]
ops ci show
ops ci doctor
ops ci credentials
ops ci env [--apply]
ops ci connect [--interactive] [--apply] [--command CMD]
ops ci secrets
ops ci ssh-key [--path PATH] [--apply]
```

Also routed from `main.sh`:

```bash
ops ssh [setup] [--interactive] [--apply]
ops credentials
```

## Source files

- `core/commands/ci.sh`

## Inputs and outputs

| Path | Content |
| --- | --- |
| `.ops.project/config/ci.json` | Non-secret metadata |
| `.ops.project/secrets/ci.env` | Local secrets (gitignored) |

## Testing

```bash
./ops.sh ci doctor
./ops.sh credentials
./ops.sh ssh --apply --command "hostname"
```

## See also

- [../setup-modules/ci.md](../setup-modules/ci.md)
