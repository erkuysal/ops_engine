# Custom stack

## Purpose

Fallback stack for services that do not match a specialized strategy or need minimal generic behavior.

## Source files

- `core/stacks/custom.sh`

## Stack ID

`custom`

## Behavior

Delegates to manifest actions or setup commands when present; otherwise uses generic PID-based stop/status patterns from run-plan defaults.

## See also

- [../core/run-plan.md](../core/run-plan.md)
