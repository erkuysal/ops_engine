# Go probe

## Purpose

Score directories for Go modules during discovery.

## Source files

- `core/probes/go.sh`

## Scoring

| Signal | Points |
| --- | --- |
| `go.mod` | +3 |
| `go.sum` | +1 |
| `main.go` | +1 |

Directories with `cmd/*` may be classified as `process_group` in discovery logic.

## See also

- [../stacks/go.md](../stacks/go.md)
