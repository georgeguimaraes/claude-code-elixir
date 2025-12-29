---
name: elixir-thinking
description: Use when writing Elixir code. Contains paradigm-shifting insights about processes, polymorphism, and the BEAM runtime that differ from OOP thinking.
---

# Elixir Architectural Thinking

Mental shifts required before writing Elixir. These insights contradict conventional OOP patterns.

## The Iron Law

```
NO PROCESS WITHOUT A RUNTIME REASON
```

Before creating a GenServer, Agent, or any process, answer YES to at least one:
1. Do I need mutable state persisting across calls?
2. Do I need concurrent execution?
3. Do I need fault isolation?

**All three are NO?** Use plain functions. Delete the process. Start over.

**No exceptions:**
- Don't create a process "for organization"
- Don't create a process "to group related functions"
- Don't create a process "because that's how I'd do it in OOP"
- Modules organize code. Processes manage runtime.

## The Three Decoupled Dimensions

**In OOP, objects couple three things together:**
- Behavior (methods)
- State (data)
- Mutability (identity that changes)

**Elixir decouples these into independent building blocks:**
| OOP Dimension | Elixir Equivalent |
|---------------|-------------------|
| Behavior | Modules (functions) |
| State | Data (structs, maps) |
| Mutability | Processes (GenServer) |

**Why this matters:** Pick only what you need. "I only need data and functions" = no process needed.

## Processes Are for Runtime, NOT Organization

> "Use processes only to model runtime properties—mutable state, concurrency, failures—**never for code organization**."

**Before creating a process, ask:**
1. Do I need mutable state persisting across calls?
2. Do I need concurrent execution?
3. Do I need fault isolation?

If none apply, use plain functions. Modules organize code; processes manage runtime.

## "Let It Crash" = "Let It Heal"

The misconception: Write careless code.

The truth: Supervisors are designed to START processes.

> "You don't need unbreakable software. You need repairable software."

- Handle expected errors explicitly (`{:ok, _}` / `{:error, _}`)
- Let unexpected errors crash → supervisor restarts
- Process linking propagates failures correctly

## Rule of Least Expressiveness

Use the simplest abstraction that solves the problem:

1. **Pattern matching** — Use if it works
2. **Anonymous functions** — Slightly more flexible
3. **Behaviors** — Multiple callbacks, named contracts
4. **Protocols** — Polymorphism over data types
5. **Message passing** — Most dynamic, least compile-time safety

Each step adds complexity. Don't reach for behaviors when pattern matching works.

## Three Polymorphism Mechanisms

| For Polymorphism Over... | Use | Contract |
|--------------------------|-----|----------|
| Modules | Behaviors | Upfront callbacks |
| Data | Protocols | Upfront implementations |
| Processes | Message passing | Implicit (send/receive) |

**Behaviors** = default for module polymorphism (very cheap at runtime)
**Protocols** = only when composing data types, especially built-ins
**Message passing** = only when stateful by design (IO, file handles)

## BEAM as Operating System

> "BEAM is an operating system for your code."

Processes are not lightweight threads—they're independent programs:
- Separate memory, stack, heap
- Separately garbage collected
- Like microservices, but no networking overhead

This enables:
- First-class cancellation: `Process.exit(pid, :kill)` with strong guarantees
- Observable runtime: SSH into running system, inspect any process
- Fair scheduling: <1ms preemptive switching, no monopolization

## Flyweight Pattern Is FREE

OOP problem: Every 'A' character as new object = memory explosion → Flyweight pattern (object pools).

**Elixir non-problem:** Immutable data = compiler automatically shares identical literals.

```elixir
def char_a do
  %Character{value: "A"}
end
# Automatically optimized: all calls share one memory location
```

## Data Modeling Replaces Class Hierarchies

OOP: Complex class hierarchy + visitor pattern.

Elixir: Model as data + pattern matching + recursion.

```elixir
{:sequence, {:literal, "rain"}, {:repeat, {:alternation, "dogs", "cats"}}}

def interpret({:literal, text}, input), do: ...
def interpret({:sequence, left, right}, input), do: ...
def interpret({:repeat, pattern}, input), do: ...
```

Tuples, atoms, and pattern matching replace entire class hierarchies.

## Decoupling Is Not Self-Serving

> "We don't decouple because we have to. We need a reason—decoupling introduces complexity."

**When justified:**
- Library needs user extensibility
- Multiple implementations coexist
- Testing requires swapping implementations

**When to stay coupled:**
- Internal module, single implementation
- Simple conditional logic works
- Pattern matching handles all cases

## Clarity Over Readability

Stop using vague terms like "readable." Use "clarity":

**Clarity test:** As a reasonably fluent reader, can I effortlessly understand:
1. The purpose (what problem it solves)
2. The solution the author chose

**Separation of concerns test:** Can each part be understood in isolation? If not, don't split.

## Testing Behavior, Not Implementation

> "The unit we're testing is the unit of behavior, not the unit of code."

- Don't test each module directly
- Test use cases / public API
- View is always implementation detail of controller
- Refactoring should not break tests (unless behavior changed)

## Keep Tests Async: Avoid Global State

`async: true` is the default for a reason—parallel tests are fast and expose hidden dependencies.

**Tests that mutate global state force `async: false`:**
```elixir
# WRONG: Forces sequential tests
Application.put_env(:my_app, :feature_flag, true)
```

**Global state that breaks async tests:**
- `Application.put_env/3` — Shared across all tests
- Module attributes at runtime
- ETS tables without isolation
- File system operations on shared paths
- External services without sandboxing

**Solutions that preserve `async: true`:**

| Problem | Solution |
|---------|----------|
| Config values | Pass config as function argument |
| Feature flags | Inject via process dictionary or context |
| ETS tables | Create per-test tables with unique names |
| External APIs | Use Mox with explicit allowances |

```elixir
# GOOD: Dependency injection
def send_email(user, mailer \\ MyApp.Mailer) do
  mailer.deliver(user.email, "Welcome!")
end

# GOOD: Config as argument
def connect(opts \\ []) do
  timeout = Keyword.get(opts, :timeout, Application.get_env(:my_app, :timeout))
  # ...
end
```

**The rule:** If you need `async: false`, you've coupled to global state. Fix the coupling, not the test.

## The Layer Architecture

Design order:
1. **Data Layer** — Core data structures first
2. **Functional Core** — Pure transformations
3. **Process Layer** — Only when concurrency/state needed
4. **API Layer** — Interface others use

Each layer independently testable and composable.

## Common Patterns Already in OTP

- **Task** — Async computation
- **Agent** — Simple state holder
- **GenServer** — Request/response with state
- **Supervisor** — Fault tolerance

Many design patterns are built into the language.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I need a process to organize this code" | Modules organize code. Processes are for runtime. |
| "GenServer is the Elixir way" | GenServer is ONE tool. Plain functions are also the Elixir way. |
| "I'll need state eventually" | YAGNI. Add process when you need it, not before. |
| "It's just a simple wrapper process" | Simple wrappers become bottlenecks. Use functions. |
| "This is how I'd structure it in OOP" | OOP patterns don't translate. Rethink from data flow. |
| "I need a singleton" | You probably need a module with functions. |
| "Behaviors require a process" | Behaviors define callbacks. Many don't need processes. |
| "I want to encapsulate this" | Modules encapsulate. Processes add runtime overhead. |
| "It feels more structured" | Structure comes from data design, not processes. |
| "Let it crash means I need processes" | Let it crash means supervisors restart. Functions can crash too. |

## Red Flags - STOP and Reconsider

- Creating process without answering the three questions
- Using GenServer for stateless operations
- Wrapping a library in a process "for safety"
- One process per entity without runtime justification
- Reaching for protocols when pattern matching works
- Adding behaviors for single implementations
- Complex class hierarchy thinking

**Any of these? Re-read The Iron Law.**
