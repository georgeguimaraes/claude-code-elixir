---
name: otp-thinking
description: Use when writing OTP code in Elixir. Contains insights about GenServer bottlenecks, supervision patterns, ETS caching, and choosing between OTP abstractions.
---

# OTP Thinking

Paradigm shifts for OTP design. These insights challenge typical concurrency and state management patterns.

## The Iron Law

```
GENSERVER IS A BOTTLENECK BY DESIGN
```

A GenServer processes ONE message at a time. Before creating one, ask:
1. Do I actually need serialized access?
2. Will this become a throughput bottleneck?
3. Can reads bypass the GenServer via ETS?

**The ETS pattern:** GenServer owns ETS table, writes serialize through GenServer, reads bypass it entirely with `:read_concurrency`.

**No exceptions:** Don't wrap stateless functions in GenServer. Don't create GenServer "for organization".

## Task.Supervisor, Not Task.async

`Task.async` spawns a **linked** process—if task crashes, caller crashes too.

| Pattern | On task crash |
|---------|---------------|
| `Task.async/1` | Caller crashes (linked, unsupervised) |
| `Task.Supervisor.async/2` | Caller crashes (linked, supervised) |
| `Task.Supervisor.async_nolink/2` | Caller survives, can handle error |

**Use Task.Supervisor for:** Production code, graceful shutdown, observability, `async_nolink`.
**Use Task.async for:** Quick experiments, scripts, when crash-together is acceptable.

## DynamicSupervisor + Registry = Named Dynamic Processes

DynamicSupervisor only supports `:one_for_one` (dynamic children have no ordering). Use Registry for names—never create atoms dynamically:

```elixir
defp via_tuple(id), do: {:via, Registry, {MyApp.Registry, id}}
```

**PartitionSupervisor** scales DynamicSupervisor for millions of children.

## :pg for Distributed, Registry for Local

| Tool | Scope | Use Case |
|------|-------|----------|
| Registry | Single node | Named dynamic processes |
| :pg | Cluster-wide | Process groups, pub/sub |

`:pg` replaced deprecated `:pg2`. **Horde** provides distributed supervisor/registry with CRDTs.

## Broadway vs Oban: Different Problems

| Tool | Use For |
|------|---------|
| Broadway | External queues (SQS, Kafka, RabbitMQ) — data ingestion with batching |
| Oban | Background jobs with database persistence |

Broadway is NOT a job queue.

### Broadway Gotchas

**Processors are for runtime, not code organization.** Dispatch to modules in `handle_message`, don't add processors for different message types.

**one_for_all is for Broadway bugs, not your code.** Your `handle_message` errors are caught and result in failed messages, not supervisor restarts.

**Handle expected failures in the producer** (connection loss, rate limits). Reserve max_restarts for unexpected bugs.

## Supervision Strategies Encode Dependencies

| Strategy | Children Relationship |
|----------|----------------------|
| :one_for_one | Independent |
| :one_for_all | Interdependent (all restart) |
| :rest_for_one | Sequential dependency |

Think about failure cascades BEFORE coding.

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

## Storage Options

| Need | Use |
|------|-----|
| Memory cache | ETS (`:read_concurrency` for reads) |
| Static config | :persistent_term (faster than ETS) |
| Disk persistence | DETS (2GB limit) |
| Transactions/Distribution | Mnesia |

## :sys Debugs ANY OTP Process

```elixir
:sys.get_state(pid)        # Current state
:sys.trace(pid, true)      # Trace events (TURN OFF when done!)
```

## Red Flags - STOP and Reconsider

- GenServer wrapping stateless computation
- Task.async in production when you need error handling
- Creating atoms dynamically for process names
- Single GenServer becoming throughput bottleneck
- Using Broadway for background jobs (use Oban)
- Using Oban for external queue consumption (use Broadway)
- No supervision strategy reasoning

**Any of these? Re-read The Iron Law and use the Abstraction Decision Tree.**
