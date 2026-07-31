# global command

## Purpose

`ops global` manages reusable machine-level VPS and Docker profiles. Profiles
are stored under `${XDG_CONFIG_HOME:-~/.config}/ops/profiles`; a project stores
only the selected profile ID and optional overrides in
`.ops.project/config/ci.json`.

```bash
ops global setup personal-vps --interactive --apply
ops global list
ops global show personal-vps
ops global use personal-vps --apply
ops global current
ops global doctor
```

A deploy path template such as `/srv/{project}` is expanded using the project
name. A project can override it while selecting the profile:

```bash
ops global use personal-vps --project-path=/srv/hemak --apply
```

## Resolution precedence

Runtime environment variables have highest priority, followed by non-empty
project values, the selected global profile, and command defaults. Changing a
global profile therefore updates every referencing project unless that project
has an explicit override.

Global profile JSON contains non-secret connection metadata and credential
references only. SSH private keys remain in `~/.ssh`; Docker passwords remain
in Docker's configured credential store or environment variables. Ops does not
copy those secret values into project configuration.

When `ops setup` or `ops ci setup --interactive` configures deployment, it
presents a numbered connection selector:

1. saved global profiles;
2. create a new reusable SSH + remote Docker Compose connection;
3. enter project-only connection values;
4. configure deployment later.

The selected profile is persisted as `global_profile` and reused until changed
with `ops global use`. A newly created connection is written only with
`--apply`. Choosing "later" records `connection_deferred: true`; the first
interactive deployment opens the selector again.

Once an applied connection is selected, setup can test SSH and remote Docker
and can hand local and remote registry authentication to `docker login`. Those
actions update Docker-native state on the selected machines, not Ops
configuration.
