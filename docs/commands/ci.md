# ci command

## Purpose

Local-first CI/deploy configuration: server metadata, credential readiness, SSH checks, optional GitHub secret guidance.

## CLI / entrypoints

```bash
ops ci setup [--interactive] [--apply] [--profile NAME] [--global-profile NAME]
ops ci setup --defer-connection --apply
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

Interactive setup selects a saved global connection, creates one, accepts
project-only values, or defers deployment configuration. Connection profiles
contain routes and credential references only; SSH keys and registry passwords
remain in their native stores.

After applying a connection, setup optionally tests SSH plus remote Docker. It
offers separate `docker login` actions for the local build machine and the
remote Docker host used by Compose pulls. Docker owns both resulting
credentials; Ops never writes the password or token into its package, global
profile, or project JSON.

## Testing

```bash
./ops.sh ci doctor
./ops.sh credentials
./ops.sh ssh --apply --command "hostname"
```

## See also

- [../setup-modules/ci.md](../setup-modules/ci.md)
