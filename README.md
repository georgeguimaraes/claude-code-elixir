# Claude Code Elixir

Claude Code plugins for Elixir development.

## Installation

```bash
claude plugins marketplace add georgeguimaraes/claude-code-elixir
```

Install all plugins:

```bash
claude plugins install elixir-lsp@claude-code-elixir
claude plugins install mix-format@claude-code-elixir
claude plugins install mix-compile@claude-code-elixir
claude plugins install elixir-architectural-thinking@claude-code-elixir
claude plugins install phoenix-ecto-thinking@claude-code-elixir
claude plugins install otp-thinking@claude-code-elixir
```

## Prerequisites

| Platform | Command |
|----------|---------|
| macOS | `brew install elixir elixir-ls` |
| Windows | `choco install elixir elixir-ls` |

> **Note:** `mix-format` and `mix-compile` require bash (Git Bash or WSL on Windows).

---

## Plugins

### Overview

| Plugin | Type | Description |
|--------|------|-------------|
| [elixir-lsp](#elixir-lsp) | LSP | Language Server with completions, go-to-definition, Dialyzer |
| [mix-format](#mix-format) | Hook | Auto-format `.ex`/`.exs` files on save |
| [mix-compile](#mix-compile) | Hook | Compile with `--warnings-as-errors` on save |
| [elixir-architectural-thinking](#elixir-architectural-thinking) | Skill | BEAM/process mental models |
| [phoenix-ecto-thinking](#phoenix-ecto-thinking) | Skill | Phoenix Scopes, Contexts, LiveView patterns |
| [otp-thinking](#otp-thinking) | Skill | GenServer, supervision, ETS patterns |

---

### Tools

#### elixir-lsp

Elixir Language Server integration powered by [elixir-ls](https://github.com/elixir-lsp/elixir-ls).

| Feature | Description |
|---------|-------------|
| Navigation | Go to definition, find references |
| Completions | With signature help and docs |
| Diagnostics | Dialyzer type checking |
| File types | `.ex`, `.exs`, `.heex`, `.leex` |

<details>
<summary>Default settings</summary>

| Option | Default | Description |
|--------|---------|-------------|
| `dialyzerEnabled` | `true` | Enable Dialyzer diagnostics |
| `fetchDeps` | `false` | Auto-fetch deps on compile |
| `suggestSpecs` | `true` | Suggest @spec annotations |

Override per-project: `.elixir_ls/settings.json`

</details>

#### mix-format

Auto-runs `mix format` after editing `.ex` and `.exs` files.

#### mix-compile

Auto-runs `mix compile --warnings-as-errors` after editing `.ex` files.

- Only `.ex` files (not `.exs` scripts/tests)
- Finds `mix.exs` by walking up directories
- Fails on warnings or errors

---

### Skills

#### elixir-architectural-thinking

Mental models for writing Elixir — how it differs from OOP.

| Concept | Insight |
|---------|---------|
| Three dimensions | Behavior, state, mutability are **decoupled** |
| Processes | For runtime (state/concurrency/faults), **not** code organization |
| "Let it crash" | Means "let it **heal**" — supervisors restart |
| Polymorphism | Behaviors → Protocols → Message passing (least to most dynamic) |
| Data modeling | Tuples + pattern matching replace class hierarchies |

<details>
<summary>Sources</summary>

- [José Valim - Gang of None](https://www.youtube.com/watch?v=4yAaHV9wQE4)
- [Saša Jurić - The Soul of Erlang and Elixir](https://www.youtube.com/watch?v=JvBT4XBdoUE)
- [Saša Jurić - Clarity](https://www.youtube.com/watch?v=6sNmJtoKDCo)
- [Designing Elixir Systems with OTP](https://pragprog.com/titles/jgotp/designing-elixir-systems-with-otp/)
- [Official Elixir Guides](https://elixir-lang.org/getting-started/)

</details>

#### phoenix-ecto-thinking

Architectural patterns for Phoenix and Ecto.

| Concept | Insight |
|---------|---------|
| Scopes (1.8+) | Security-first authorization threading |
| mount vs handle_params | mount = setup, handle_params = data (avoid duplicate queries) |
| Contexts | Bounded domains with their own "dialect" |
| Cross-context refs | Use IDs, not `belongs_to` associations |
| PubSub | Topics **must** be scoped for multi-tenancy |

<details>
<summary>Sources</summary>

- [Phoenix 1.8 Scopes](https://hexdocs.pm/phoenix/scopes.html)
- [Phoenix Contexts Guide](https://hexdocs.pm/phoenix/contexts.html)
- [German Velasco - DDD for Phoenix Contexts](https://www.youtube.com/watch?v=mSgZ2LJXfew) (ElixirConf 2024)
- [Ecto Multi-Tenancy Guide](https://hexdocs.pm/ecto/multi-tenancy-with-query-prefixes.html)

</details>

#### otp-thinking

OTP design patterns and when to use each abstraction.

| Concept | Insight |
|---------|---------|
| GenServer | Bottleneck **by design** — processes ONE message at a time |
| ETS | Bypasses bottleneck — concurrent reads with `:read_concurrency` |
| Task.Supervisor | THE pattern for async work (not raw `Task.async`) |
| Registry + DynamicSupervisor | Named dynamic processes without atom leaks |
| Broadway vs Oban | External queues vs background jobs — different problems |

<details>
<summary>Sources</summary>

- [Erlang OTP Design Principles](https://www.erlang.org/doc/system/design_principles.html)
- [Elixir GenServer Docs](https://hexdocs.pm/elixir/GenServer.html)
- [Elixir School - OTP Concurrency](https://elixirschool.com/en/lessons/advanced/otp_concurrency)
- [Saša Jurić - Elixir in Action](https://www.manning.com/books/elixir-in-action-third-edition)
- [Stephen Bussey - Real-Time Phoenix](https://pragprog.com/titles/sbsockets/real-time-phoenix/)

</details>

---

## Troubleshooting

**elixir-ls not found:** Ensure Homebrew bin is in PATH:

```bash
export PATH="/opt/homebrew/bin:$PATH"
```
