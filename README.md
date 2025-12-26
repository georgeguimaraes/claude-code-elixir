# Claude Code Elixir

Claude Code plugins for Elixir development.

## Installation

Add the marketplace:

```bash
claude plugins marketplace add georgeguimaraes/claude-code-elixir
```

Install plugins:

```bash
claude plugins install elixir-lsp@claude-code-elixir
claude plugins install mix-format@claude-code-elixir
claude plugins install mix-compile@claude-code-elixir
claude plugins install elixir-architectural-thinking@claude-code-elixir
claude plugins install phoenix-ecto-thinking@claude-code-elixir
claude plugins install otp-thinking@claude-code-elixir
```

## Prerequisites

**macOS:**
```bash
brew install elixir elixir-ls
```

**Windows:**
```powershell
choco install elixir elixir-ls
```

> **Note:** The `mix-format` and `mix-compile` plugins require a bash environment (Git Bash, WSL). The `elixir-lsp` plugin works natively on Windows.

## Plugins

### elixir-lsp

Elixir Language Server integration powered by [elixir-ls](https://github.com/elixir-lsp/elixir-ls).

**Features:**
- Go to definition, find references, hover documentation
- Completions with signature help
- Dialyzer diagnostics

**Supported files:** `.ex`, `.exs`, `.heex`, `.leex`

**Default settings:**

| Option | Default | Description |
|--------|---------|-------------|
| `dialyzerEnabled` | `true` | Enable Dialyzer diagnostics |
| `fetchDeps` | `false` | Auto-fetch deps on compile |
| `suggestSpecs` | `true` | Suggest @spec annotations |

For project-specific settings, create `.elixir_ls/settings.json` in your project root.

### mix-format

Automatically runs `mix format` after editing `.ex` and `.exs` files.

### mix-compile

Runs `mix compile --warnings-as-errors` after editing `.ex` files. Catches compiler warnings and errors immediately.

**Notes:**
- Only runs on `.ex` files (not `.exs` scripts/tests)
- Finds `mix.exs` by walking up from the edited file
- 60-second timeout for large projects
- Fails the hook if compilation errors or warnings occur

### elixir-architectural-thinking

Architectural thinking skill for writing Elixir code. Contains paradigm-shifting insights about processes, polymorphism, and the BEAM runtime that differ from OOP thinking.

**Key concepts:**
- Three decoupled dimensions (behavior, state, mutability)
- Processes are for runtime, NOT organization
- "Let It Crash" = "Let It Heal"
- Rule of least expressiveness
- Data modeling replaces class hierarchies

**Sources:**
- [José Valim - Gang of None: Patterns of the Functional Mind](https://www.youtube.com/watch?v=4yAaHV9wQE4)
- [Saša Jurić - The Soul of Erlang and Elixir](https://www.youtube.com/watch?v=JvBT4XBdoUE)
- [Saša Jurić - Clarity (Code BEAM SF 2020)](https://www.youtube.com/watch?v=6sNmJtoKDCo)
- [Designing Elixir Systems with OTP](https://pragprog.com/titles/jgotp/designing-elixir-systems-with-otp/) by James Edward Gray II and Bruce Tate
- [Official Elixir Guides](https://elixir-lang.org/getting-started/)

### phoenix-ecto-thinking

Architectural thinking skill for Phoenix/Ecto code. Contains insights about Scopes, Contexts, LiveView lifecycle, and DDD patterns.

**Key concepts:**
- Scopes (Phoenix 1.8+) for security-first patterns
- mount/3 vs handle_params/3 (avoid duplicate queries)
- Contexts as bounded domains with dialects
- Cross-context references via IDs, not associations
- PubSub topics must be scoped for multi-tenancy

**Sources:**
- [Phoenix 1.8 Scopes Documentation](https://hexdocs.pm/phoenix/scopes.html)
- [Phoenix Contexts Guide](https://hexdocs.pm/phoenix/contexts.html)
- [German Velasco - DDD Concepts for Phoenix Contexts](https://www.youtube.com/watch?v=mSgZ2LJXfew) (ElixirConf 2024)
- [Ecto Multi-Tenancy Guide](https://hexdocs.pm/ecto/multi-tenancy-with-query-prefixes.html)

### otp-thinking

OTP design patterns skill. Contains insights about GenServer bottlenecks, supervision patterns, ETS caching, and choosing between OTP abstractions.

**Key concepts:**
- GenServer is a bottleneck BY DESIGN (processes ONE message at a time)
- ETS bypasses the bottleneck (concurrent reads)
- Task.Supervisor.async is THE pattern
- Registry + DynamicSupervisor = named dynamic processes
- Broadway vs Oban: different problems (external queues vs background jobs)

**Sources:**
- [Erlang OTP Design Principles](https://www.erlang.org/doc/system/design_principles.html)
- [Elixir GenServer Documentation](https://hexdocs.pm/elixir/GenServer.html)
- [Elixir School - OTP Concurrency](https://elixirschool.com/en/lessons/advanced/otp_concurrency)
- [Saša Jurić - Elixir in Action](https://www.manning.com/books/elixir-in-action-third-edition)
- [Cogini Blog - GenServer Bottleneck Pattern](https://www.cogini.com/blog/)
- [Stephen Bussey - Real-Time Phoenix](https://pragprog.com/titles/sbsockets/real-time-phoenix/)

## Troubleshooting

**elixir-ls not found:** Ensure Homebrew bin is in PATH:

```bash
export PATH="/opt/homebrew/bin:$PATH"
```
