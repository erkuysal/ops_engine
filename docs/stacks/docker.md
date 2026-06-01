# Docker stack

## Purpose

Compose-based services: up/down/logs/status via `docker compose`.

## Source files

- `core/stacks/docker.sh`

## Stack ID

`docker`

## Default commands

| Action | Default |
| --- | --- |
| start | `docker compose up -d` |
| stop | `docker compose down` |
| logs | `docker compose logs -f` |
| status | `docker compose ps --services --filter status=running` |

If `compose_files` is present on a docker service, each command uses `docker compose -f ...` with those files.

## See also

- [../probes/docker.md](../probes/docker.md)
