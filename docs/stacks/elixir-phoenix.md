# Elixir Phoenix stack

## Purpose

Run Phoenix apps: `mix phx.server`, tests, releases.

## Source files

- `core/stacks/elixir-phoenix.sh`

## Stack ID

`elixir-phoenix` (dispatch: `elixir_phoenix_dispatch`)

## Default commands

| Action | Default |
| --- | --- |
| start | `mix phx.server` |
| test | `mix test` |
| build | `mix release` |

## See also

- [../probes/elixir-phoenix.md](../probes/elixir-phoenix.md)
