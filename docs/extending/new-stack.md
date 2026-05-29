# Adding a runtime stack

## Purpose

Steps to run services for a new technology via `ops run` / `ops start`.

## Steps

1. Create `core/stacks/<stack-id>.sh` implementing `<stack_id>_dispatch` (hyphens → underscores).

2. Add defaults in `run_plan_stack_default_command` in `core/lib/run_plan.sh`.

3. Add probe (see [new-probe.md](new-probe.md)).

4. Register stack name in `validate.sh` semantic pass if applicable.

5. Document under `docs/stacks/<stack-id>.md`.

## Dispatch contract

```bash
my_stack_dispatch() {
  local action="$1"
  case "${action}" in
    start)  ... ;;
    stop)   ... ;;
    *) die "Unsupported action: ${action}" ;;
  esac
}
```

Export `OPS_SERVICE_ID` and cwd before running tools.

## Do not

Embed project-specific service names or paths in the stack file.

## Testing

```bash
./ops.sh show start <service_with_new_stack>
./ops.sh run start <service_with_new_stack> --mode foreground
```

## See also

- [../core/stacks.md](../core/stacks.md)
