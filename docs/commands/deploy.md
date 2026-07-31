# deploy command

## Purpose

Native basic remote container deploy for compose-backed services.

## CLI / entrypoints

```bash
ops deploy
ops deploy backend
ops deploy infra backend
ops deploy --service=infra
ops deploy --service=infra --compose-service=backend
ops deploy --service=infra --pull-only
ops deploy --service=infra --no-pull
ops deploy --service=infra --build --no-start
ops deploy --non-interactive
ops deploy --json
```

## Source files

- `core/commands/deploy.sh`
- `core/lib/container_pipeline.sh`

## Behavior

`ops deploy` reads compose-backed services from
`.ops.project/config/services.json`, then uses deploy metadata from
`.ops.project/config/ci.json` and `.ops.project/secrets/ci.env`.

For each selected compose target, it runs on the remote server:

```bash
cd DEPLOY_PATH
VERSION=<tag> docker compose -f FILE pull
VERSION=<tag> docker compose -f FILE build # with --build
VERSION=<tag> docker compose -f FILE up -d
```

Before running remote commands, `ops deploy` prints a deployment plan that shows:

- selected tag
- SSH remote and deploy path
- whether pull, build, and start are enabled
- selected compose files and selected compose service, or `<all>`

`ops deploy <name>` follows the same target resolution as `ops build <name>`:
an exact `.ops` service id wins first, then ops searches compose service names
inside configured `compose_files` and direct compose files under each service
path. When a compose service is selected, it appends that service to `pull` and
`up -d`, so only that compose service is deployed.

This first native deploy slice intentionally does not sync compose files or env
files. Keep using existing project workflows for sync until a native `ops sync`
slice exists.

Stages always run in pull → build → start order. `--no-start` prepares images
without activation, while `--pull-only` retains its existing pull-only behavior.
Plans that disable every stage are rejected.

Before planning, deploy verifies that host, user, and remote path resolve from
environment, project configuration, or the selected global connection. When
they are missing in an interactive terminal, deploy launches the same
connection selector used by setup and then resumes. In CI, JSON mode, or with
`--non-interactive`, it exits with setup commands instead of prompting.

## Testing

```bash
bash tests/run.sh
./ops.sh deploy --service=infra --dry-run
```
