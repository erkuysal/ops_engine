# Adding a discovery probe

## Purpose

Steps to fingerprint a new technology during workspace discovery.

## Steps

1. Create `core/probes/<stack-id>.sh` with:
   - `probe_<id>_stack_id` — print stack string (use underscores in function name if id has hyphens, e.g. `probe_elixir_phoenix_stack_id` for `elixir-phoenix`)
   - `probe_<id>_score_dir <dir>` — print integer score

2. Source or invoke the probe from `core/lib/discovery.sh` in the probe loop (match existing probes).

3. Add stack to validate allowlist in `core/commands/validate.sh` if enforced.

4. Add stack strategy doc under `docs/stacks/` and probe doc under `docs/probes/`.

5. Update [schemas-and-templates.md](schemas-and-templates.md) if manifest schema lists stacks.

## Example scoring

See [../probes/django.md](../probes/django.md) — favor strong signals (+3) and weak signals (+1).

## Testing

```bash
./ops.sh setup discover
jq '.directories[] | select(.stack == "your-stack")' .ops.project/generated/discovery.json
```

## See also

- [../core/probes.md](../core/probes.md)
- [new-stack.md](new-stack.md)
