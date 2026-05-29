# Node probe

## Purpose

Score directories for Node/npm projects during discovery.

## Source files

- `core/probes/node.sh`

## Scoring

| Signal | Points |
| --- | --- |
| `package.json` | +3 |
| `yarn.lock` | +1 |
| `pnpm-lock.yaml` | +1 |
| `package-lock.json` | +1 |
| `node_modules/` | +1 |

Discovery may classify Electron apps and workspace roots separately in `discovery.sh`.

## See also

- [../stacks/node.md](../stacks/node.md)
