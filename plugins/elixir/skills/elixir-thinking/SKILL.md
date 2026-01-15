---
name: elixir-thinking
description: This skill should be used when the user asks to "implement a feature in Elixir", "refactor this module", "should I use a GenServer here?", "how should I structure this?", "use the pipe operator", "add error handling", "make this concurrent", or mentions protocols, behaviours, pattern matching, with statements, comprehensions, structs, or coming from an OOP background. Contains paradigm-shifting insights.
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

## Control Flow

**Pattern matching first:**
- Match on function heads instead of `if/else` or `case` in bodies
- `%{}` matches ANY map—use `map_size(map) == 0` guard for empty maps
- Avoid nested `case`—refactor to single `case`, `with`, or separate functions

**Error handling:**
- Use `{:ok, result}` / `{:error, reason}` for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining `{:ok, _}` / `{:error, _}` operations

**Be explicit about expected cases:**
- Avoid `_ -> nil` catch-alls—they silently swallow unexpected cases
- Avoid `value && value.field` nil-punning—obscures actual return types
- When a case has `{:ok, nil} -> nil` alongside `{:ok, value} -> value.field`, use `with` instead:

```elixir
# Verbose
case get_run(id) do
  {:ok, nil} -> nil
  {:ok, run} -> run.recommendations
end

# Prefer
with {:ok, %{recommendations: recs}} <- get_run(id), do: recs
```

## Polymorphism

| For Polymorphism Over... | Use | Contract |
|--------------------------|-----|----------|
| Modules | Behaviors | Upfront callbacks |
| Data | Protocols | Upfront implementations |
| Processes | Message passing | Implicit (send/receive) |

**Behaviors** = default for module polymorphism (very cheap at runtime)
**Protocols** = only when composing data types, especially built-ins
**Message passing** = only when stateful by design (IO, file handles)

Use the simplest abstraction: pattern matching → anonymous functions → behaviors → protocols → message passing. Each step adds complexity.

**When justified:** Library extensibility, multiple implementations, test swapping.
**When to stay coupled:** Internal module, single implementation, pattern matching handles all cases.

## Data Modeling Replaces Class Hierarchies

OOP: Complex class hierarchy + visitor pattern.
Elixir: Model as data + pattern matching + recursion.

```elixir
{:sequence, {:literal, "rain"}, {:repeat, {:alternation, "dogs", "cats"}}}

def interpret({:literal, text}, input), do: ...
def interpret({:sequence, left, right}, input), do: ...
def interpret({:repeat, pattern}, input), do: ...
```

## Defaults and Options

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

Don't create helper functions to merge config defaults. Inline the fallback:

```elixir
# WRONG
defp merge_defaults(opts), do: Keyword.merge([repo: Application.get_env(:app, :repo)], opts)

# RIGHT
def some_function(opts) do
  repo = opts[:repo] || Application.get_env(:app, :repo)
end
```

## Idioms

- Process dictionary is typically unidiomatic—pass state explicitly
- Reserve `is_thing` names for guards only
- Use structs over maps when shape is known: `defstruct [:name, :age]`
- Prepend to lists `[new | list]` not `list ++ [new]`
- Use `dbg/1` for debugging—prints formatted value with context
- Use built-in `JSON` module (Elixir 1.18+) instead of Jason

## Testing

**Test behavior, not implementation.** Test use cases / public API. Refactoring shouldn't break tests.

**Test your code, not the framework.** If deleting your code doesn't fail the test, it's tautological.

**Keep tests async.** `async: false` means you've coupled to global state. Fix the coupling:

| Problem | Solution |
|---------|----------|
| `Application.put_env` | Pass config as function argument |
| Feature flags | Inject via process dictionary or context |
| ETS tables | Create per-test tables with unique names |
| External APIs | Use Mox with explicit allowances |
| File system operations | Use `@tag :tmp_dir` (see below) |

**Use `tmp_dir` for file tests.** ExUnit creates unique temp directories per test, async-safe:

```elixir
@tag :tmp_dir
test "writes file", %{tmp_dir: tmp_dir} do
  path = Path.join(tmp_dir, "test.txt")
  File.write!(path, "content")
  assert File.read!(path) == "content"
end
```

Directory is auto-cleaned before each run. Works with `@moduletag :tmp_dir` for all tests in module.

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
