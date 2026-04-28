---
name: phoenix-thinking
description: This skill should be used when the user asks to "add a LiveView page", "create a form", "handle real-time updates", "broadcast changes to users", "add a new route", "create an API endpoint", "fix this LiveView bug", "why is mount called twice?", or mentions handle_event, handle_info, handle_params, mount, channels, controllers, components, assigns, sockets, or PubSub. Covers where to load data (mount vs handle_params) and the LiveView lifecycle.
---

# Phoenix Thinking

Mental shifts for Phoenix applications. These insights challenge typical web framework patterns.

## Where to Load Data: mount vs handle_params

Default: load data in `mount/3`.

```elixir
def mount(_params, _session, socket) do
  posts = Blog.list_posts(socket.assigns.current_scope)
  {:ok, assign(socket, posts: posts)}
end
```

Yes, mount runs twice on initial load (HTTP dead render + WebSocket connect). So does `handle_params/3`. That's the LiveView lifecycle, not a bug to route around. Moving queries from mount to handle_params does not dedupe them.

Use `handle_params/3` for data that changes on live navigation (`push_patch` / `<.link patch={...}>`). mount does not re-run on patches, handle_params does.

```elixir
def handle_params(%{"filter" => filter}, _uri, socket) do
  posts = Blog.list_posts(socket.assigns.current_scope, filter)
  {:noreply, assign(socket, posts: posts, filter: filter)}
end
```

When the initial double-load actually matters, the real tools are:
- `connected?(socket)` to gate work to the connected render (loses SEO / no-JS rendering)
- `assign_async/3` to load after mount returns, in a separate process
- `assign_new/3` to reuse values already set on `conn.assigns` by upstream Plugs (e.g. `:current_user`), or shared from a parent LiveView. It does not dedupe arbitrary work across the dead/connected boundary: the function still runs on connected mount.

```elixir
def mount(_params, _session, socket) do
  posts = if connected?(socket), do: Blog.list_posts(socket.assigns.current_scope), else: []
  {:ok, assign(socket, posts: posts)}
end
```

## Scopes: Security-First Pattern (Phoenix 1.8+)

Scopes address OWASP #1 vulnerability: Broken Access Control. Authorization context is threaded automatically—no more forgetting to scope queries.

```elixir
def list_posts(%Scope{user: user}) do
  Post |> where(user_id: ^user.id) |> Repo.all()
end
```

## PubSub Topics Must Be Scoped

```elixir
def subscribe(%Scope{organization: org}) do
  Phoenix.PubSub.subscribe(@pubsub, "posts:org:#{org.id}")
end
```

Unscoped topics = data leaks between tenants.

## External Polling: GenServer, Not LiveView

**Bad:** Every connected user makes API calls (multiplied by users).
**Good:** Single GenServer polls, broadcasts to all via PubSub.

## Components Receive Data, LiveViews Own Data

- **Functional components:** Display-only, no internal state
- **LiveComponents:** Own state, handle own events
- **LiveViews:** Full page, owns URL, top-level state

## Async Data Loading

Use `assign_async/3` for data that can load after mount:

```elixir
def mount(_params, _session, socket) do
  {:ok, assign_async(socket, :user, fn -> {:ok, %{user: fetch_user()}} end)}
end
```

## Gotchas from Core Team

### LiveView terminate/2 Requires trap_exit

`terminate/2` only fires if you're trapping exits—which you shouldn't do in LiveView.

**Fix:** Use a separate GenServer that monitors the LiveView process via `Process.monitor/1`, then handle `:DOWN` messages to run cleanup.

### start_async Duplicate Names: Later Wins

Calling `start_async` with the same name while a task is in-flight: the **later one wins**, the previous task's result is ignored.

**Fix:** Call `cancel_async/3` first if you want to abort the previous task.

### Channel Intercept Socket State is Stale

The socket in `handle_out` intercept is a snapshot from subscription time, not current state.

**Why:** Socket is copied into fastlane lookup at subscription time for performance.

**Fix:** Use separate topics per role, or fetch current state explicitly.

### CSS Class Precedence is Stylesheet Order

When merging classes on components, precedence is determined by **stylesheet order**, not HTML order. If `btn-primary` appears later in the compiled CSS than `bg-red-500`, it wins regardless of HTML order.

**Fix:** Use variant props instead of class merging.

### Upload Content-Type Can't Be Trusted

The `:content_type` in `%Plug.Upload{}` is user-provided. Always validate actual file contents (magic bytes) and rewrite filename/extension.

### Read Body Before Plug.Parsers for Webhooks

To verify webhook signatures, you need the raw body. But Plug.Parsers consumes it.

```elixir
{:ok, body, conn} = Plug.Conn.read_body(conn)
verify_signature!(conn, body)
%{conn | body_params: JSON.decode!(body)}
```

Don't use `preserve_req_body: true`—it keeps the entire body in memory for ALL requests.

## Red Flags - STOP and Reconsider

- Loading patch-mutable data in mount/3 instead of handle_params/3
- Unscoped PubSub topics in multi-tenant app
- LiveView polling external APIs directly
- Using terminate/2 for cleanup (won't fire without trap_exit)
- Calling start_async with same name without cancel_async first
- Relying on socket.assigns in Channel intercepts (stale!)
- CSS class merging for component customization (use variants)
- Trusting `%Plug.Upload{}.content_type` for security

**Any of these? Re-read the Gotchas section.**
