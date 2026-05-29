# graph library

## Purpose

Service dependency graph: topological order for `ops start` / `ops stop`.

## Source files

- `core/lib/graph.sh`

## Key behavior

- Reads `depends_on` from manifest or `services.json`
- Used by `start.sh` for `--with-deps` ordering
- Detects cycles for validation

## See also

- [../commands/start.md](../commands/start.md)
- [../setup-modules/dependencies.md](../setup-modules/dependencies.md)
