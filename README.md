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
```

## Prerequisites

- Elixir and Erlang (`brew install elixir`)
- elixir-ls for LSP (`brew install elixir-ls`)

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

## Troubleshooting

**elixir-ls not found:** Ensure Homebrew bin is in PATH:

```bash
export PATH="/opt/homebrew/bin:$PATH"
```
