# Elixir Phoenix probe

## Purpose

Score directories for Phoenix/Elixir projects during discovery.

## Source files

- `core/probes/elixir-phoenix.sh`

## Stack ID

`elixir-phoenix` (function prefix `probe_elixir_phoenix_`)

## Scoring

| Signal | Points |
| --- | --- |
| `mix.exs` | +3 |
| `config/config.exs` | +2 |
| `lib/*_web` directory | +2 |
| `config/runtime.exs` | +1 |

## See also

- [../stacks/elixir-phoenix.md](../stacks/elixir-phoenix.md)
