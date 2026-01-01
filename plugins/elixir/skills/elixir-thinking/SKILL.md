---
name: elixir-thinking
description: Use when writing Elixir code. Contains paradigm-shifting insights about processes, polymorphism, and the BEAM runtime that differ from OOP thinking.
---

# Elixir Thinking

Mental shifts required before writing Elixir. These contradict conventional OOP patterns.

## The Iron Law

```
NO PROCESS WITHOUT A RUNTIME REASON
```

Before creating a GenServer, Agent, or any process, answer YES to at least one:
1. Do I need mutable state persisting across calls?
2. Do I need concurrent execution?
3. Do I need fault isolation?

**All three are NO?** Use plain functions. Modules organize code; processes manage runtime.

## The Three Decoupled Dimensions

OOP couples behavior, state, and mutability together. Elixir decouples them:

| OOP Dimension | Elixir Equivalent |
|---------------|-------------------|
| Behavior | Modules (functions) |
| State | Data (structs, maps) |
| Mutability | Processes (GenServer) |

Pick only what you need. "I only need data and functions" = no process needed.

## "Let It Crash" = "Let It Heal"

The misconception: Write careless code.
The truth: Supervisors START processes.

- Handle expected errors explicitly (`{:ok, _}` / `{:error, _}`)
- Let unexpected errors crash → supervisor restarts

## Rule of Least Expressiveness

Use the simplest abstraction: pattern matching → anonymous functions → behaviors → protocols → message passing. Each step adds complexity.

## Three Polymorphism Mechanisms

| For Polymorphism Over... | Use | Contract |
|--------------------------|-----|----------|
| Modules | Behaviors | Upfront callbacks |
| Data | Protocols | Upfront implementations |
| Processes | Message passing | Implicit (send/receive) |

**Behaviors** = default for module polymorphism (very cheap at runtime)
**Protocols** = only when composing data types, especially built-ins
**Message passing** = only when stateful by design (IO, file handles)

## Data Modeling Replaces Class Hierarchies

OOP: Complex class hierarchy + visitor pattern.
Elixir: Model as data + pattern matching + recursion.

```elixir
{:sequence, {:literal, "rain"}, {:repeat, {:alternation, "dogs", "cats"}}}

def interpret({:literal, text}, input), do: ...
def interpret({:sequence, left, right}, input), do: ...
def interpret({:repeat, pattern}, input), do: ...
```

## Decoupling Is Not Self-Serving

**When justified:** Library extensibility, multiple implementations, test swapping.
**When to stay coupled:** Internal module, single implementation, pattern matching handles all cases.

## Testing

**Test behavior, not implementation.** Test use cases / public API. Refactoring shouldn't break tests.

**Keep tests async.** `async: false` means you've coupled to global state. Fix the coupling:

| Problem | Solution |
|---------|----------|
| `Application.put_env` | Pass config as function argument |
| Feature flags | Inject via process dictionary or context |
| ETS tables | Create per-test tables with unique names |
| External APIs | Use Mox with explicit allowances |

## Inline Config Defaults

Don't create helper functions to merge config defaults. Inline the fallback:

```elixir
# WRONG: Unnecessary indirection
defp merge_defaults(opts), do: Keyword.merge([repo: Application.get_env(:app, :repo)], opts)

# RIGHT: Explicit about which keys each function uses
def some_function(opts) do
  repo = opts[:repo] || Application.get_env(:app, :repo)
end
```

## Use Default Values, Not Nil Checks

Use `/3` variants (`Keyword.get/3`, `Map.get/3`) instead of case statements branching on `nil`:

```elixir
# WRONG
case Keyword.get(opts, :chunker) do
  nil -> chunker()
  config -> parse_chunker_config(config)
end

# RIGHT
Keyword.get(opts, :chunker, :default) |> parse_chunker_config()
```

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I need a process to organize this code" | Modules organize code. Processes are for runtime. |
| "GenServer is the Elixir way" | Plain functions are also the Elixir way. |
| "I'll need state eventually" | YAGNI. Add process when you need it. |
| "It's just a simple wrapper process" | Simple wrappers become bottlenecks. |
| "This is how I'd structure it in OOP" | Rethink from data flow. |

## Red Flags - STOP and Reconsider

- Creating process without answering the three questions
- Using GenServer for stateless operations
- Wrapping a library in a process "for safety"
- One process per entity without runtime justification
- Reaching for protocols when pattern matching works

**Any of these? Re-read The Iron Law.**
