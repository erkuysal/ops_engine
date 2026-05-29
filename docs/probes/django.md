# Django probe

## Purpose

Score directories for Django projects during discovery.

## Source files

- `core/probes/django.sh`

## Functions

- `probe_django_stack_id` → `django`
- `probe_django_score_dir <dir>`

## Scoring

| Signal | Points |
| --- | --- |
| `manage.py` | +3 |
| `requirements.txt` | +2 |
| `Pipfile` | +2 |
| `pyproject.toml` | +1 |
| `setup.py` | +1 |

## See also

- [../core/probes.md](../core/probes.md)
- [../stacks/django.md](../stacks/django.md)
