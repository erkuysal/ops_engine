# monitor command

## Purpose

Lightweight read-only monitoring checks for services and infrastructure targets.

## CLI / entrypoints

```bash
ops monitor status
ops monitor status --json
ops monitor status --target web.tcp
ops monitor test
ops monitor test --strict
ops monitor hosts --port=5173
ops monitor setup
ops monitor setup --apply
ops monitor setup --postgres --redis --apply
ops monitor setup --postgres-db=app --postgres-user=app --redis-db=1 --apply
ops monitor setup --postgres-user=postgres --postgres-no-password --apply
ops monitor setup --postgres-user=admin --postgres-password=admin --apply
ops monitor setup --service-host=web=<host-visible-from-monitor> --apply
ops monitor setup --interactive --apply
ops monitor postgres info
ops monitor postgres databases
ops monitor postgres users
ops monitor doctor
ops monitor credentials
```

## Source files

- `core/commands/monitor.sh`

## Target sources

`ops monitor status` derives targets from current service config:

- `healthcheck` becomes an HTTP target
- `setup.port` becomes a TCP target on `127.0.0.1`

It also reads optional configured targets from:

```text
.ops.project/config/monitoring.json
```

Generate that file from current service healthchecks and ports with:

```bash
ops monitor setup --apply
```

Add local Postgres/Redis monitor targets and a local secrets template with:

```bash
ops monitor setup --postgres --redis --apply
```

Default local values are:

| Target | Value |
| --- | --- |
| Postgres host | `127.0.0.1` |
| Postgres port | `5432` |
| Postgres database | `postgres` |
| Postgres user | `postgres` |
| Postgres password | empty |
| Redis host | `127.0.0.1` |
| Redis port | `6379` |
| Redis DB | `0` |
| Redis password | empty |

For prompted values, use:

```bash
ops monitor setup --interactive --apply
```

Interactive setup asks which optional infra targets to configure, then prompts
for connection values. Password prompts are hidden and empty input means no
password.

For scripted setup, pass connection details as flags:

```bash
ops monitor setup \
  --postgres-host=127.0.0.1 \
  --postgres-port=5432 \
  --postgres-db=app \
  --postgres-user=app \
  --postgres-no-password \
  --redis-host=127.0.0.1 \
  --redis-port=6379 \
  --redis-db=0 \
  --apply
```

For local/dev defaults, you can also set password values directly:

```bash
ops monitor setup --postgres-user=postgres --postgres-no-password --apply
ops monitor setup --postgres-user=admin --postgres-password=admin --apply
ops monitor setup --redis-password=admin --apply
```

Use direct password flags only for local/dev convenience. Shell commands may be
recorded in history. For anything sensitive, use `ops monitor setup
--interactive --apply` or edit `.ops.project/secrets/infra.env` locally.

Custom env-var names are supported:

```bash
ops monitor setup \
  --postgres-db-env=PGDATABASE \
  --postgres-user-env=PGUSER \
  --postgres-password-env=PGPASSWORD \
  --redis-db-env=REDIS_DATABASE \
  --redis-password-env=REDIS_PASS \
  --apply
```

Secrets are not written to `monitoring.json`. The monitor config stores env-var
references such as `POSTGRES_PASSWORD` and `REDIS_PASSWORD`; prompted local
values live in:

```text
.ops.project/secrets/infra.env
```

If `infra.env` already exists, setup upserts the selected Postgres/Redis keys
instead of replacing the file.

## Host overrides

Derived TCP targets default to `127.0.0.1` from the shell where `ops monitor`
runs. Under WSL, that means WSL localhost. If a dev server is running on
Windows localhost, the browser may reach it while WSL sees `127.0.0.1:PORT` as
closed.

Use a host override to keep the derived port but change the host:

```bash
ops monitor setup --service-host=web=<windows-host-ip> --apply
ops monitor setup --target-host=web.tcp=<windows-host-ip> --apply
```

Inside WSL, the Windows host is often available from:

```bash
ops monitor hosts --port=5173
```

Use the first candidate that reports `up` as the override host.

Example:

```json
{
  "version": "1",
  "env_file": ".ops.project/secrets/infra.env",
  "targets": [
    {
      "id": "postgres.local",
      "kind": "postgres",
      "host": "127.0.0.1",
      "port": 5432,
      "db_env": "POSTGRES_DB",
      "user_env": "POSTGRES_USER",
      "password_env": "POSTGRES_PASSWORD"
    },
    {
      "id": "redis.local",
      "kind": "redis",
      "host": "127.0.0.1",
      "port": 6379,
      "db_env": "REDIS_DB",
      "password_env": "REDIS_PASSWORD"
    }
  ]
}
```

Supported target kinds:

- `http`
- `tcp`
- `postgres`
- `redis`

Postgres checks use `pg_isready` with optional database, user, and password from
the referenced env vars. Redis checks use `redis-cli ping`, optional logical DB
from `REDIS_DB`, and `REDISCLI_AUTH` when `REDIS_PASSWORD` is set.

## Test mode

`ops monitor status` is observational and exits 0 after reporting target state.
`ops monitor test` runs the same checks but exits 1 when any target is `down`.
Unknown targets, such as missing optional tools or unsupported kinds, are
reported but do not fail unless `--strict` is set.

```bash
ops monitor test --target postgres.local
ops monitor test --strict
ops monitor test --json
```

## Doctor

`ops monitor doctor` reports optional checker tools:

- `curl`
- `timeout`
- `pg_isready`
- `redis-cli`

## Credentials

`ops monitor credentials` checks Postgres/Redis monitor targets and reports
whether referenced env vars are set. Values are never printed.

## Postgres inspection

`ops monitor postgres info` explains the configured Postgres target, env-var
references, optional tool availability, and readiness state. Password values are
never printed.

```bash
ops monitor postgres info
ops monitor postgres info --json
```

When `psql` is installed and the configured credentials can connect, list
databases and users with:

```bash
ops monitor postgres databases
ops monitor postgres users
ops monitor postgres databases --json
ops monitor postgres users --json
```

If no Postgres target exists yet, create one first:

```bash
ops monitor setup --postgres --apply
```

## Testing

```bash
bash tests/run.sh
./ops.sh monitor status --json
```
