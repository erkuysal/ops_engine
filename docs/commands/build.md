# build command

## Purpose

Native container build/push basics for configured services.

## CLI / entrypoints

```bash
ops build
ops build backend
ops build infra backend
ops build --service=backend --tag=1.2.3
ops build --service=infra --compose-service=backend --tag=1.2.3
ops build --service=backend --tag=1.2.3 --push
ops build --all --push --no-cache
ops build --json
```

## Source files

- `core/commands/build.sh`
- `core/lib/container_pipeline.sh`

## Behavior

`ops build` reads `.ops.project/config/services.json` and selects services with
either:

- a Dockerfile from `build.dockerfile`, `deploy.dockerfile`, or
  `<service path>/Dockerfile`
- compose files from `compose_files`, or standard compose filenames directly
  under the service path

Dockerfile services run `docker build`, and `--push` adds `docker push`.
Compose services run `VERSION=<tag> docker compose build`, and `--push` adds
`VERSION=<tag> docker compose push`.

Before running commands, `ops build` prints a build plan that shows:

- selected tag, push mode, and cache mode
- selected target name
- Dockerfile target image, context, and Dockerfile
- compose target compose files and selected compose service, or `<all>`

`ops build <name>` first looks for an `.ops` service id. If no exact service id
matches, it looks for a compose service with that name inside configured
`compose_files` and direct compose files under each service path. For example,
if `frontend` is a service inside `frontend/web/docker-compose.yml`,
`ops build frontend` plans the owning `web` target and scopes the compose
command to `frontend`.

Use `ops build <ops-service> <compose-service>` or
`--service=<ops-service> --compose-service=<compose-service>` when you want to
select a compose file group explicitly.

Image names come from `deploy.image` or `build.image` when configured. If no
explicit image is present, ops derives one from `.ops.project/config/ci.json`
Docker metadata:

```text
<registry>/<namespace>/<image_prefix>-<service>:<tag>
```

For `docker.io`, the registry prefix is omitted.

## Testing

```bash
bash tests/run.sh
./ops.sh build --service=backend --dry-run
```
