# Docker probe

## Purpose

Score directories for Docker/Compose layouts during discovery.

## Source files

- `core/probes/docker.sh`

## Scoring

| Signal | Points |
| --- | --- |
| `Dockerfile` | +3 |
| `docker-compose.yml` | +1 |
| `docker-compose.yaml` | +1 |

## See also

- [../stacks/docker.md](../stacks/docker.md)
