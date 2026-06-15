# Go stack

## Purpose

Run Go services: single binary (`go run`) or **process_group** with cross-compiled outputs under `.ops.project/generated/bin/<service>/`.

## Source files

- `core/stacks/go.sh`
- `core/lib/cross_shell.sh` (WSL/Windows Go)

## Stack ID

`go`

## process_group

When `runner.kind` is `process_group`:

- `build.outputs[]` — name + package path per binary
- `run.processes[]` — which processes to start
- Default output dir: `.ops.project/generated/bin/<service_id>`
- Per-process logs: `.ops.project/logs/<service_id>/<process>.log`
- Per-process PIDs: `.ops.project/run/<service_id>/<process>.pid`

## Default commands

| Action | Default |
| --- | --- |
| start | `go run main.go` (single-process) |
| build | `go build -o app` |
| test | `go test ./...` |

## Extension points

Keep project-specific binary logic out of consuming repos; extend `_go_dispatch` and cross-shell helpers.

## Testing

```bash
./ops.sh show start <service_id>
./ops.sh start <service_id> --dry-run
```

## See also

- [../core/cross-shell.md](../core/cross-shell.md)
- [../probes/go.md](../probes/go.md)
