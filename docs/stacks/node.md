# Node stack

## Purpose

Run Node/npm frontends and apps: `npm start`, build, test, lint.

## Source files

- `core/stacks/node.sh`

## Stack ID

`node`

## Default commands

| Action | Default |
| --- | --- |
| start | `npm start` |
| build | `npm run build` |
| test | `npm test` |
| lint | `npm run lint` |

Setup may override start with `setup.services.<id>.command` (e.g. `npm run dev`).

## See also

- [../probes/node.md](../probes/node.md)
