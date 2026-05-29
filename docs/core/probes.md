# Probes overview

## Purpose

Small scripts that score how well a directory matches a stack fingerprint during discovery.

## Source files

| Probe | Stack ID |
| --- | --- |
| `core/probes/django.sh` | `django` |
| `core/probes/go.sh` | `go` |
| `core/probes/node.sh` | `node` |
| `core/probes/elixir-phoenix.sh` | `elixir-phoenix` |
| `core/probes/docker.sh` | `docker` |

## Contract

Each probe implements:

- `probe_<name>_stack_id` — returns stack string
- `probe_<name>_score_dir <dir>` — returns integer score (higher = better match)

Discovery picks the highest-scoring probe per directory.

## Per-probe docs

- [../probes/django.md](../probes/django.md)
- [../probes/go.md](../probes/go.md)
- [../probes/node.md](../probes/node.md)
- [../probes/elixir-phoenix.md](../probes/elixir-phoenix.md)
- [../probes/docker.md](../probes/docker.md)

## Extension points

[extending/new-probe.md](../extending/new-probe.md)

## See also

- [discovery.md](discovery.md)
