# Django stack

## Purpose

Run Django API services: `runserver`, tests, stop via PID files.

## Source files

- `core/stacks/django.sh`

## Stack ID

`django`

## Default commands

From `run_plan_stack_default_command`:

| Action | Default |
| --- | --- |
| start | `python -u manage.py runserver 0.0.0.0:8000` |
| test | `python manage.py test` |
| stop | PID from `.ops.project/run/<service_id>.pid` |

## Inputs and outputs

**Logs:** `.ops.project/logs/<service_id>.log`  
**PID:** `.ops.project/run/<service_id>.pid`

Conda activation may be applied via `setup_runtime_python_activation`.

## Testing

```bash
./ops.sh show start backend
./ops.sh start backend --dry-run
```

## See also

- [../probes/django.md](../probes/django.md)
- [../core/stacks.md](../core/stacks.md)
