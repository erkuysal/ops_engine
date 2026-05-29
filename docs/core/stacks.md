# Stacks overview

## Purpose

Stack strategies implement runtime actions (`start`, `stop`, `logs`, `build`, …) per technology. `run.sh` dispatches to `<stack>_dispatch` in `core/stacks/<stack>.sh`.

## Source files

| Stack | File |
| --- | --- |
| django | `core/stacks/django.sh` |
| go | `core/stacks/go.sh` |
| node | `core/stacks/node.sh` |
| elixir-phoenix | `core/stacks/elixir-phoenix.sh` |
| docker | `core/stacks/docker.sh` |
| custom | `core/stacks/custom.sh` |

## Dispatch convention

Stack file must define:

```bash
<stack_id_with_underscores>_dispatch() {
  local action="$1"
  ...
}
```

Example: `elixir-phoenix` → `elixir_phoenix_dispatch`.

## Special cases

- **go** — `process_group` runner: multiple binaries from `build.outputs` and `run.processes`
- **custom** — fallback for unknown or minimal stacks

## Default commands

Defined in `run_plan_stack_default_command` in `core/lib/run_plan.sh`.

## Per-stack docs

- [../stacks/django.md](../stacks/django.md)
- [../stacks/go.md](../stacks/go.md)
- [../stacks/node.md](../stacks/node.md)
- [../stacks/elixir-phoenix.md](../stacks/elixir-phoenix.md)
- [../stacks/docker.md](../stacks/docker.md)
- [../stacks/custom.md](../stacks/custom.md)

## Extension points

[extending/new-stack.md](../extending/new-stack.md)

## See also

- [run-plan.md](run-plan.md)
