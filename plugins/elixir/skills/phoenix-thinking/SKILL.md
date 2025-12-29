---
name: phoenix-thinking
description: Use when writing Phoenix, LiveView, or Plug code. Contains insights about LiveView lifecycle, Scopes, PubSub, and gotchas from Chris McCord.
---

# Phoenix Architectural Thinking

Mental shifts for Phoenix applications. These insights challenge typical web framework patterns.

## The Iron Law

```
NO DATABASE QUERIES IN MOUNT
```

mount/3 is called TWICE (HTTP request + WebSocket connection). Queries in mount = duplicate queries.

**The pattern:**
- `mount/3` = setup only (empty assigns, subscriptions, defaults)
- `handle_params/3` = data loading (all database queries)

**No exceptions:**
- Don't query "just this one small thing" in mount
- Don't "optimize later"
- Don't assume mount is called once
- LiveView lifecycle is non-negotiable

## mount/3 vs handle_params/3: The Duplicate Query Problem

**Critical insight:** mount is called TWICE (HTTP + WebSocket).

```elixir
def mount(_params, _session, socket) do
  # NO database queries here! Called twice.
  {:ok, assign(socket, posts: [], loading: true)}
end

def handle_params(params, _uri, socket) do
  # Database queries here - once per navigation
  posts = Blog.list_posts(socket.assigns.scope)
  {:noreply, assign(socket, posts: posts, loading: false)}
end
```

**mount/3 = setup** (empty assigns, subscriptions)
**handle_params/3 = data loading** (queries, URL-driven state)

## Scopes: Security-First Pattern (Phoenix 1.8+)

Scopes address OWASP #1 vulnerability: Broken Access Control.

**Before 1.8:** You had to remember to scope every query (easy to forget and leak data).

**With Scopes:** Authorization context is threaded automatically.

```elixir
# Scope contains user/org for every request
def list_posts(%Scope{user: user}) do
  Post |> where(user_id: ^user.id) |> Repo.all()
end
```

All generators (`phx.gen.live`, etc.) automatically scope functions.

## PubSub Topics Must Be Scoped

```elixir
def subscribe(%Scope{organization: org}) do
  Phoenix.PubSub.subscribe(@pubsub, "posts:org:#{org.id}")
end

defp broadcast(%Scope{} = scope, event, payload) do
  Phoenix.PubSub.broadcast(@pubsub, topic_for(scope), {event, payload})
end
```

Unscoped topics = data leaks between tenants.

## External Polling: GenServer, Not LiveView

**Bad:** Every connected user makes API calls (multiplied by users).

**Good:** Single GenServer polls, broadcasts to all.

```elixir
defmodule ExternalDataPoller do
  use GenServer

  def handle_info(:poll, state) do
    data = ExternalAPI.fetch()
    Phoenix.PubSub.broadcast(MyApp.PubSub, "external_data", {:update, data})
    schedule_poll()
    {:noreply, state}
  end
end
```

## Components Receive Data, LiveViews Own Data

- **Functional components:** Display-only, no internal state
- **LiveComponents:** Own state, handle own events
- **LiveViews:** Full page, owns URL, top-level state

> "Create functional components that depend on assigns from LiveView rather than fetching data inside components."

## Gotchas from Core Team

Counterintuitive behaviors documented by Chris McCord.

### LiveView terminate/2 Requires trap_exit

`terminate/2` only fires if you're trapping exits—which you shouldn't do in LiveView.

```elixir
# This won't fire on normal LiveView shutdown:
def terminate(_reason, _socket) do
  cleanup()  # Never called!
end
```

**The fix:** Use a separate GenServer that monitors the LiveView process:

```elixir
defmodule MyApp.LiveMonitor do
  use GenServer

  def monitor(pid, module, meta) do
    GenServer.call(__MODULE__, {:monitor, pid, module, meta})
  end

  def handle_call({:monitor, pid, module, meta}, _, %{views: views} = state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | views: Map.put(views, pid, {module, meta})}}
  end

  def handle_info({:DOWN, _, :process, pid, reason}, %{views: views} = state) do
    case Map.pop(views, pid) do
      {{module, meta}, new_views} ->
        Task.start(fn -> module.unmount(meta, reason) end)
        {:noreply, %{state | views: new_views}}
      {nil, _} -> {:noreply, state}
    end
  end
end

# In LiveView:
def mount(_, _, socket) do
  if connected?(socket) do
    MyApp.LiveMonitor.monitor(self(), __MODULE__, %{user_id: socket.assigns.current_user.id})
  end
  {:ok, socket}
end

def unmount(%{user_id: user_id}, _reason), do: :ok  # Cleanup here
```

### start_async Duplicate Names: Later Wins

Calling `start_async` with the same name while a task is in-flight: the **later one wins**, the previous task's result is ignored.

```elixir
socket
|> start_async(:fetch, fn -> fetch_v1() end)
|> start_async(:fetch, fn -> fetch_v2() end)  # v2 wins, v1's result ignored
```

The first task keeps running but its result won't trigger `handle_async`.

**Fix:** Call `cancel_async/3` first if you want to abort the previous task.

### Channel Intercept Socket State is Stale

The socket in `handle_out` intercept is **not** the current socket—it's a snapshot from subscription time.

```elixir
# WRONG - socket.assigns is stale here!
def handle_out("new_msg", payload, socket) do
  if socket.assigns.user_role == :admin do  # This role might be outdated!
    {:noreply, socket}
  end
end
```

**Why:** Socket is copied into fastlane lookup at subscription time for performance.

**Fix:** Use separate topics or fetch current state explicitly:

```elixir
def handle_in("subscribe", _, socket) do
  topic = if socket.assigns.role == :admin, do: "room:1:admin", else: "room:1:user"
  {:noreply, assign(socket, :topic, topic)}
end
```

### LongPoll Fallback is Memoized in sessionStorage

If WebSocket fails once (even in dev due to slow compilation), LongPoll is used for the entire browser session.

**Symptom:** "Why is my app using LongPoll? WebSocket works fine now!"

**Why:** Corporate proxies sometimes accept WS upgrade then drop traffic. Memoization avoids repeated 2.5s timeout.

**Fix for dev:**
```javascript
longPollFallbackMs: location.host.startsWith("localhost") ? undefined : 2500
```

### CSS Class Precedence is Stylesheet Order

When merging classes on components, precedence is determined by **stylesheet order**, not HTML order.

```elixir
# This doesn't reliably override:
<.button class="bg-red-500">  # Might not override btn-primary's bg color
```

If `btn-primary` appears later in the compiled CSS than `bg-red-500`, it wins regardless of HTML order.

**Fix:** Use variant props instead of class merging:

```elixir
attr :variant, :string, default: "primary", values: ~w(primary secondary danger)
attr :size, :string, default: "md", values: ~w(sm md lg)

def button(assigns) do
  ~H"""
  <button class={["btn", @variant, @size]}>
    <%= render_slot(@inner_block) %>
  </button>
  """
end
```

### Upload Content-Type Can't Be Trusted

> "A malicious user can always say the mime type is a image/jpg and then send an .exe."

The `:content_type` in `%Plug.Upload{}` is user-provided. Always validate actual file contents (magic bytes) and rewrite filename/extension.

### Read Body Before Plug.Parsers for Webhooks

To verify webhook signatures, you need the raw body. But Plug.Parsers consumes it.

**Pattern:** Read and verify before Plug.Parsers:

```elixir
{:ok, body, conn} = Plug.Conn.read_body(conn)
verify_signature!(conn, body)
%{conn | body_params: Jason.decode!(body)}
```

Don't use `preserve_req_body: true`—it keeps the entire body in memory for ALL requests.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I'll query in mount, it's simpler" | mount is called twice. Use handle_params. |
| "I don't need Scopes for this" | Scopes prevent OWASP #1. Use them. |
| "PubSub topics don't need scoping" | Unscoped topics = data leaks. Always scope. |
| "LiveView can poll the external API" | One GenServer polls, broadcasts to all. Don't multiply requests. |

## Red Flags - STOP and Reconsider

- Database query in mount/3
- Unscoped PubSub topics in multi-tenant app
- LiveView polling external APIs directly
- Skipping Scopes "for simplicity"
- Using terminate/2 for cleanup (won't fire without trap_exit)
- Calling start_async with same name without cancel_async first
- Relying on socket.assigns in Channel intercepts (stale!)
- CSS class merging for component customization (use variants)
- Trusting `%Plug.Upload{}.content_type` for security
- Using `preserve_req_body: true` with file uploads

**Any of these? Re-read The Iron Law and the Gotchas section.**
