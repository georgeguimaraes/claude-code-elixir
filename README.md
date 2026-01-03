# Claude Code Elixir

Claude Code plugins for Elixir development.

## Installation

```bash
claude plugin marketplace add georgeguimaraes/claude-code-elixir
```

Install all plugins:

```bash
claude plugin install elixir-lsp@claude-code-elixir && \
claude plugin install mix-format@claude-code-elixir && \
claude plugin install mix-compile@claude-code-elixir && \
claude plugin install mix-credo@claude-code-elixir && \
claude plugin install elixir@claude-code-elixir
```

## Prerequisites

| Platform | Command |
|----------|---------|
| macOS | `brew install elixir elixir-ls` |
| Windows | `choco install elixir elixir-ls` |
| Any (mise) | `mise use -g elixir-ls` |

> **Note:** `mix-format`, `mix-compile`, and `mix-credo` require bash (Git Bash or WSL on Windows).

---

## Plugins

### Overview

| Plugin | Type | Description |
|--------|------|-------------|
| [elixir-lsp](#elixir-lsp) | LSP | Language Server with completions, go-to-definition, Dialyzer |
| [mix-format](#mix-format) | Hook | Auto-format `.ex`/`.exs` files on save |
| [mix-compile](#mix-compile) | Hook | Compile with `--warnings-as-errors` on save |
| [mix-credo](#mix-credo) | Hook | Run Credo code quality checks on save |
| [elixir](#elixir) | Skills | BEAM architecture, Phoenix, Ecto, OTP patterns |

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

#### mix-credo

Auto-runs `mix credo` after editing `.ex` and `.exs` files to check code quality.

- Runs on both `.ex` and `.exs` files
- Uses project's default Credo configuration
- Gracefully skips if Credo is not installed
- Fails on code quality issues

---

### Skills

#### elixir

Paradigm-shifting skills for Elixir, Phoenix, and OTP development. Includes a SessionStart hook that auto-suggests skills when working on Elixir code.

**Included skills:**

| Skill | Use When |
|-------|----------|
| `elixir-thinking` | Designing modules, processes, data structures |
| `phoenix-thinking` | Working with Phoenix, LiveView, PubSub |
| `ecto-thinking` | Working with Ecto, contexts, schemas |
| `otp-thinking` | Implementing GenServers, supervisors, Tasks |

##### elixir-thinking

Mental models for writing Elixir — how it differs from OOP.

| Concept | Insight |
|---------|---------|
| **Iron Law** | NO PROCESS WITHOUT A RUNTIME REASON |
| Three dimensions | Behavior, state, mutability are **decoupled** |
| Processes | For runtime (state/concurrency/faults), **not** code organization |
| "Let it crash" | Means "let it **heal**" — supervisors restart |
| Polymorphism | Behaviors → Protocols → Message passing (least to most dynamic) |

<details>
<summary>Sources</summary>

- [José Valim - Gang of None](https://www.youtube.com/watch?v=4yAaHV9wQE4)
- [Saša Jurić - The Soul of Erlang and Elixir](https://www.youtube.com/watch?v=JvBT4XBdoUE)
- [Saša Jurić - Clarity](https://www.youtube.com/watch?v=6sNmJtoKDCo)
- [Designing Elixir Systems with OTP](https://pragprog.com/titles/jgotp/designing-elixir-systems-with-otp/)
- [Official Elixir Guides](https://elixir-lang.org/getting-started/)

</details>

##### phoenix-thinking

Architectural patterns for Phoenix and LiveView.

| Concept | Insight |
|---------|---------|
| **Iron Law** | NO DATABASE QUERIES IN MOUNT |
| Scopes (1.8+) | Security-first authorization threading |
| mount vs handle_params | mount = setup, handle_params = data |
| PubSub | Scoped topics, `broadcast_from` to avoid self-broadcast |
| Channel fastlane | Socket state can be stale — re-fetch or include in broadcast |

<details>
<summary>Sources</summary>

- [Phoenix 1.8 Scopes](https://hexdocs.pm/phoenix/scopes.html)
- [Phoenix LiveView Docs](https://hexdocs.pm/phoenix_live_view)
- [Stephen Bussey - Real-Time Phoenix](https://pragprog.com/titles/sbsockets/real-time-phoenix/)

</details>

##### ecto-thinking

Architectural patterns for Ecto and contexts.

| Concept | Insight |
|---------|---------|
| Contexts | Bounded domains with their own "dialect" |
| Cross-context refs | Use IDs, not `belongs_to` associations |
| Schemas | Multiple changesets per schema, `embedded_schema` for forms |
| Preloads | Separate vs join — pick based on data shape |
| pool_count vs pool_size | pool_count = DBConnection pools, pool_size = connections per pool |

<details>
<summary>Sources</summary>

- [Phoenix Contexts Guide](https://hexdocs.pm/phoenix/contexts.html)
- [German Velasco - DDD for Phoenix Contexts](https://www.youtube.com/watch?v=mSgZ2LJXfew) (ElixirConf 2024)
- [Ecto Multi-Tenancy Guide](https://hexdocs.pm/ecto/multi-tenancy-with-query-prefixes.html)

</details>

##### otp-thinking

OTP design patterns and when to use each abstraction.

| Concept | Insight |
|---------|---------|
| **Iron Law** | GENSERVER IS A BOTTLENECK BY DESIGN |
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

---

## License

Copyright (c) 2025 George Guimarães

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
