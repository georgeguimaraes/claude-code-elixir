---
name: oban
description: Build and debug durable background jobs with Oban and Oban Pro. Use for workers, job argument serialization, retries, scheduled or recurring jobs, uniqueness, batches, and workflows. Use otp for in-memory tasks and process supervision.
---

# Oban

Handle durable jobs, serialization, failures, and workflow composition with Oban.

---

# Part 1: Oban (Non-Pro)

## The Iron Law: JSON Serialization

```
JOB ARGS ARE JSON. ATOMS BECOME STRINGS.
```

This single fact causes most Oban debugging headaches.

```elixir
# Creating - atom keys are fine
MyWorker.new(%{user_id: 123})

# Processing - must use string keys (JSON converted atoms to strings)
def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
  # ...
end
```

## Error Handling: Let It Crash

**Don't catch errors in Oban jobs.** Let them bubble up to Oban for proper handling.

### Why?

1. **Automatic logging**: Oban logs the full error with stacktrace
2. **Automatic retries**: Jobs retry with exponential backoff
3. **Visibility**: Failed jobs appear in Oban Web dashboard
4. **Consistency**: Error states are tracked in the database

### Anti-Pattern

```elixir
# Bad: Swallowing errors
def perform(%Oban.Job{} = job) do
  case do_work(job.args) do
    {:ok, result} -> {:ok, result}
    {:error, reason} ->
      Logger.error("Failed: #{reason}")
      {:ok, :failed}  # Silently marks as complete!
  end
end
```

### Correct Pattern

```elixir
# Good: Let errors propagate
def perform(%Oban.Job{} = job) do
  result = do_work!(job.args)  # Raises on failure
  {:ok, result}
end

# Or return error tuple - Oban treats as failure
def perform(%Oban.Job{} = job) do
  case do_work(job.args) do
    {:ok, result} -> {:ok, result}
    {:error, reason} -> {:error, reason}  # Oban will retry
  end
end
```

### When to Catch Errors

Only catch errors when you need custom retry logic or want to mark a job as permanently failed:

```elixir
def perform(%Oban.Job{} = job) do
  case external_api_call(job.args) do
    {:ok, result} -> {:ok, result}
    {:error, :not_found} -> {:cancel, :resource_not_found}  # Don't retry
    {:error, :rate_limited} -> {:snooze, 60}  # Retry in 60 seconds
    {:error, _} -> {:error, :will_retry}  # Normal retry
  end
end
```

## Snoozing for Polling

Use `{:snooze, seconds}` for polling external state instead of manual retry logic:

```elixir
def perform(%Oban.Job{} = job) do
  if external_thing_finished?(job.args) do
    {:ok, :done}
  else
    {:snooze, 5}  # Check again in 5 seconds
  end
end
```

## Simple Job Chaining

For simple sequential chains (JobA → JobB → JobC), have each job enqueue the next:

```elixir
def perform(%Oban.Job{} = job) do
  result = do_work(job.args)
  # Enqueue next job on success
  NextWorker.new(%{data: result}) |> Oban.insert()
  {:ok, result}
end
```

**Don't reach for Oban Pro Workflows for linear chains.**

## Unique Jobs

Prevent duplicate jobs with the `unique` option:

```elixir
use Oban.Worker,
  queue: :default,
  unique: [period: 60]  # Only one job with same args per 60 seconds

# Or scope uniqueness to specific fields
unique: [period: 300, keys: [:user_id]]
```

**Gotcha:** Uniqueness is checked on insert, not execution. Two identical jobs inserted 61 seconds apart will both run.

## High Throughput: Chunking

For millions of records, **chunk work into batches** rather than one job per item:

```elixir
# Bad: One job per contact (millions of jobs = database strain)
Enum.each(contacts, &ContactWorker.new(%{id: &1.id}) |> Oban.insert())

# Good: Chunk into batches
contacts
|> Enum.chunk_every(100)
|> Enum.each(&BatchWorker.new(%{contact_ids: Enum.map(&1, fn c -> c.id end)}) |> Oban.insert())
```

Use bulk inserts without uniqueness constraints for maximum throughput.

---

# Part 2: Oban Pro

## Cascade Context: Erlang Term Serialization

Unlike regular job args, **cascade context preserves atoms**:

```elixir
# Creating - atom keys
Workflow.put_context(%{score_run_id: id})

# Processing - atom keys still work!
def my_cascade(%{score_run_id: id}) do
  # ...
end

# Dot notation works too
def later_step(context) do
  context.score_run_id
  context.previous_result
end
```

### Serialization Summary

| | Creating | Processing |
|-----------------|----------|--------------|
| Regular jobs | atoms ok | strings only |
| Cascade context | atoms ok | atoms ok |

## When to Use Workflows

Reserve Workflows for:
- Complex dependency graphs (not just linear chains)
- Fan-out/fan-in patterns
- When you need recorded values across steps
- Conditional branching based on runtime state

**Don't use Workflows for simple A → B → C chains.**

## Workflow Composition with Graft

When you need a parent workflow to wait for a sub-workflow to complete before continuing, use `add_graft` instead of `add_workflow`.

### Key Differences

| Method | Sub-workflow completes before deps run? | Output accessible? |
|--------|----------------------------------------|-------------------|
| `add_workflow` | No - just inserts jobs | No |
| `add_graft` | Yes - waits for all jobs | Yes, via recorded values |

### Pattern: Composing Independent Concerns

Don't couple unrelated concerns (e.g., notifications) to domain-specific workflows (e.g., scoring). Instead, create a higher-level orchestrator:

```elixir
# Bad: Notification logic buried in AggregateScores
defmodule AggregateScores do
  def workflow(score_run_id) do
    Workflow.new()
    |> Workflow.add(:aggregate, AggregateJob.new(...))
    |> Workflow.add(:send_notification, SendEmail.new(...), deps: :aggregate)  # Wrong place!
  end
end

# Good: Higher-level workflow composes scoring + notification
defmodule FullRunWithNotifications do
  def workflow(site_url, opts) do
    notification_opts = build_notification_opts(opts)

    Workflow.new()
    |> Workflow.put_context(%{notification_opts: notification_opts})
    |> Workflow.add_graft(:scoring, &graft_full_run/1)
    |> Workflow.add_cascade(:send_notification, &send_notification/1, deps: :scoring)
  end

  defp graft_full_run(context) do
    # Sub-workflow doesn't know about notifications
    FullRun.workflow(context.site_url, context.opts)
    |> Workflow.apply_graft()
    |> Oban.insert_all()
  end
end
```

### Recording Values for Dependent Steps

For a grafted workflow's output to be available to dependent steps, the final job must use `recorded: true`:

```elixir
defmodule FinalJob do
  use Oban.Pro.Worker, queue: :default, recorded: true

  def perform(%Oban.Job{} = job) do
    # Return value becomes available in context
    {:ok, %{score_run_id: score_run_id, composite_score: score}}
  end
end
```

## Dynamic Workflow Appending

Add jobs to a running workflow with `Workflow.append/2`:

```elixir
def perform(%Oban.Job{} = job) do
  if needs_extra_step?(job.args) do
    job
    |> Workflow.append()
    |> Workflow.add(:extra, ExtraWorker.new(%{}), deps: [:current_step])
    |> Oban.insert_all()
  end
  {:ok, :done}
end
```

**Caveat:** Cannot override context or add dependencies to already-running jobs. For complex dynamic scenarios, check external state in the job itself.

## Fan-Out/Fan-In with Batches

To run a final job after multiple paginated workflows complete, use Batch callbacks:

```elixir
# Wrap workflows in a shared batch
batch_id = "import-#{import_id}"

pages
|> Enum.each(fn page ->
  PageWorkflow.workflow(page)
  |> Batch.from_workflow(batch_id: batch_id)
  |> Oban.insert_all()
end)

# Add completion callback
Batch.new(batch_id: batch_id)
|> Batch.add_callback(:completed, CompletionWorker)
|> Oban.insert()
```

**Tip:** Include pagination workers in the batch to prevent premature completion.

## Testing Workflows

**Don't use inline testing mode** - workflows need database interaction.

```elixir
# Use run_workflow/1 for integration tests
assert %{completed: 3} =
  Workflow.new()
  |> Workflow.add(:a, WorkerA.new(%{}))
  |> Workflow.add(:b, WorkerB.new(%{}), deps: [:a])
  |> Workflow.add(:c, WorkerC.new(%{}), deps: [:b])
  |> run_workflow()
```

For testing recorded values between workers, insert predecessor jobs with pre-filled metadata.

---

# Red Flags - STOP and Reconsider

**Non-Pro:**
- Pattern matching on atom keys in `perform/1`
- Catching all errors and returning `{:ok, _}`
- Wrapping job logic in try/rescue
- Creating one job per item when processing millions of records

**Pro:**
- Using `add_workflow` when you need to wait for completion
- Coupling notifications/emails to domain workflows
- Not using `recorded: true` when you need output from grafted workflows
- Using Workflows for simple linear job chains
- Testing workflows with inline mode

**Any of these? Re-read the serialization rules.**
