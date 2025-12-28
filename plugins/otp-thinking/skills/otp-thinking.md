---
name: otp-thinking
description: Use when writing OTP code in Elixir. Contains insights about GenServer bottlenecks, supervision patterns, ETS caching, and choosing between OTP abstractions that differ from typical concurrency thinking.
---

# OTP Architectural Thinking

Paradigm shifts for OTP design. These insights challenge typical concurrency and state management patterns.

## The Iron Law

```
GENSERVER IS A BOTTLENECK BY DESIGN
```

A GenServer processes ONE message at a time. This is intentional—it serializes access.

**Before creating a GenServer, ask:**
1. Do I actually need serialized access?
2. Will this become a throughput bottleneck?
3. Can reads bypass the GenServer via ETS?

**The ETS pattern:** GenServer owns ETS table, writes serialize through GenServer, reads bypass it entirely.

**No exceptions:**
- Don't wrap stateless functions in GenServer
- Don't create GenServer "for organization"
- Don't assume "it's fine for now"—design for load

**The Calculator Anti-Pattern:**
```elixir
# WRONG: Creates bottleneck for no reason
defmodule Calculator do
  use GenServer
  def add(a, b), do: GenServer.call(__MODULE__, {:add, a, b})
end
```

No state needed = no GenServer needed. Use `def add(a, b), do: a + b`.

**Warning signs your GenServer is a bottleneck:**
- Mailbox filling up (check in Observer/LiveDashboard)
- Timeouts on calls
- Message queue length growing

## ETS Bypasses the Bottleneck

The pattern: GenServer owns ETS, writes serialize through GenServer, reads bypass it entirely.

```elixir
def init(_) do
  :ets.new(:cache, [:named_table, :public, read_concurrency: true])
  {:ok, nil}
end

# Writes through GenServer (serialized)
def put(key, value), do: GenServer.call(__MODULE__, {:put, key, value})

# Reads bypass GenServer (concurrent!)
def get(key) do
  case :ets.lookup(:cache, key) do
    [{^key, value}] -> {:ok, value}
    [] -> :error
  end
end
```

`:read_concurrency` optimizes for concurrent reads. This is THE solution to GenServer bottlenecks.

## Task.Supervisor.async Is THE Pattern

Not `Task.async`. The supervised version is recommended:

```elixir
# Supervision tree
{Task.Supervisor, name: MyApp.TaskSupervisor}

# Usage
task = Task.Supervisor.async(MyApp.TaskSupervisor, fn ->
  expensive_work()
end)
result = Task.await(task, 30_000)
```

**For error handling without crashing caller:**
```elixir
task = Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn -> might_fail() end)

case Task.yield(task, 5000) || Task.shutdown(task) do
  {:ok, result} -> {:ok, result}
  {:exit, reason} -> {:error, reason}
  nil -> {:error, :timeout}
end
```

## DynamicSupervisor Only Supports :one_for_one

Makes sense—dynamic children have no ordering relationships.

**Use DynamicSupervisor for:**
- User sessions
- WebSocket connections
- Per-entity processes (chat rooms, game rooms)
- Potentially millions of children

## PartitionSupervisor Scales DynamicSupervisor

When starting millions of children, single DynamicSupervisor becomes bottleneck:

```elixir
{PartitionSupervisor, child_spec: DynamicSupervisor, name: MyApp.Supervisors}

# Routes by key hash
DynamicSupervisor.start_child(
  {:via, PartitionSupervisor, {MyApp.Supervisors, user_id}},
  child_spec
)
```

## Registry + DynamicSupervisor = Named Dynamic Processes

Don't create atoms dynamically. Use Registry:

```elixir
defp via_tuple(id), do: {:via, Registry, {MyApp.Registry, id}}

def start_link(id) do
  GenServer.start_link(__MODULE__, id, name: via_tuple(id))
end
```

Processes auto-unregister on death.

## :pg for Distributed, Registry for Local

| Tool | Scope | Use Case |
|------|-------|----------|
| Registry | Single node | Named dynamic processes |
| :pg | Cluster-wide | Process groups, pub/sub |

`:pg` replaced `:pg2` (deprecated OTP 23). It's what Phoenix.PubSub uses.

```elixir
:pg.join(:my_scope, :room_123, self())
members = :pg.get_members(:my_scope, :room_123)
```

## Horde for Distributed Supervisor/Registry

Standard DynamicSupervisor and Registry are node-local.

**Horde provides:**
- `Horde.DynamicSupervisor` — Distributed supervisor
- `Horde.Registry` — Distributed registry
- CRDT-based (eventually consistent)
- Auto-redistribution on node failure

**Swarm is deprecated** — doesn't re-register processes that restart outside handoff.

## Broadway vs Oban: Different Problems

| Tool | Use For |
|------|---------|
| Broadway | External queues (SQS, Kafka, RabbitMQ) |
| Oban | Background jobs with database persistence |

- "Send welcome email after signup" → **Oban**
- "Process messages from SQS" → **Broadway**

Broadway is NOT a job queue. It's a data ingestion pipeline with batching and backpressure.

## GenStateMachine for Explicit State Machines

Use `gen_statem` when you have explicit states + transitions:

```elixir
def handle_event(:cast, :connect, :disconnected, data) do
  {:next_state, :connecting, data, [{:state_timeout, 5000, :timeout}]}
end

def handle_event(:state_timeout, :timeout, :connecting, data) do
  {:next_state, :disconnected, data}
end
```

State timeouts are first-class. Better than rolling your own with `Process.send_after`.

## :sys Module Debugs ANY OTP Process

```elixir
:sys.get_state(pid)        # Current state
:sys.trace(pid, true)      # Trace events
:sys.statistics(pid, true) # Start collecting stats
:sys.suspend(pid)          # Pause processing

# CRITICAL: Turn off when done!
:sys.no_debug(pid)
```

Excessive debug handlers seriously damage performance.

## :persistent_term Is Faster Than ETS

For truly static, read-heavy data:

```elixir
:persistent_term.put(:config, %{...})
:persistent_term.get(:config)
```

Faster reads than ETS. Data persists past crashes. Use for configuration, lookup tables.

## ETS vs DETS vs Mnesia

| Need | Use |
|------|-----|
| Memory cache | ETS |
| Disk persistence | DETS (2GB limit) |
| Transactions | Mnesia |
| Distribution | Mnesia |
| RAM + disk | Mnesia (configurable per table) |

## Supervision Strategies Encode Dependencies

| Strategy | Children Relationship |
|----------|----------------------|
| :one_for_one | Independent |
| :one_for_all | Interdependent (all restart) |
| :rest_for_one | Sequential dependency |

Think about failure cascades BEFORE coding.

## Agent vs GenServer

Agent is GenServer under the hood.

| Use Agent | Use GenServer |
|-----------|---------------|
| Simple state (Map, counter) | Complex callbacks |
| Prototyping | Production |
| Would use Enum operations | Need handle_info, init logic |

If Agent feels clunky, extracting to GenServer is straightforward.

## Abstraction Decision Tree

```
Need state?
├── No → Plain function
└── Yes → Complex behavior?
    ├── No → Agent
    └── Yes → Supervision?
        ├── No → spawn_link
        └── Yes → Request/response?
            ├── No → Task.Supervisor
            └── Yes → Explicit states?
                ├── No → GenServer
                └── Yes → GenStateMachine
```

## Pooling: When Resources Have Limits

Use Poolboy/NimblePool when:
- Database connection limits
- External API rate limits
- Expensive initialization

```elixir
:poolboy.transaction(:worker_pool, fn worker ->
  GenServer.call(worker, :do_work)
end)
```

## Telemetry Is Built Into Everything

Phoenix, Ecto, and most libraries emit telemetry events. Attach handlers:

```elixir
:telemetry.attach("my-handler", [:phoenix, :endpoint, :stop], &handle/4, nil)
```

Use Telemetry.Metrics + reporters (StatsD, Prometheus, LiveDashboard).

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "GenServer is the Elixir way" | GenServer is ONE tool. It's a bottleneck by design. |
| "Task.async is simpler" | Task.Supervisor.async is THE recommended pattern. |
| "I'll add ETS later if needed" | Design for load now. Retrofitting is harder. |
| "DynamicSupervisor needs strategies" | DynamicSupervisor only supports :one_for_one. That's fine. |
| "I need atoms for process names" | Registry exists. Never create atoms dynamically. |
| "Oban is overkill, I'll use Broadway" | Different tools. Oban = jobs, Broadway = external queues. |
| "I'll use :pg2 for distribution" | :pg2 is deprecated. Use :pg. |
| "Poolboy for everything" | Pools are for limited resources. Most things don't need pools. |
| "I need a process per user" | Only if you need state/concurrency/isolation per user. |
| "Agent is too simple" | Agent IS GenServer. Extract when you need callbacks. |

## Red Flags - STOP and Reconsider

- GenServer wrapping stateless computation
- Task.async without supervision
- Creating atoms dynamically for process names
- Single GenServer becoming throughput bottleneck
- Using Broadway for background jobs (use Oban)
- Using Oban for external queue consumption (use Broadway)
- Skipping the decision tree for OTP abstractions
- No supervision strategy reasoning

**Any of these? Re-read The Iron Law and use the Abstraction Decision Tree.**
