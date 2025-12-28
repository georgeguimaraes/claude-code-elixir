---
name: phoenix-ecto-thinking
description: Use when writing Phoenix/Ecto code. Contains insights about Scopes, Contexts, LiveView lifecycle, and DDD patterns that differ from typical web framework thinking.
---

# Phoenix & Ecto Architectural Thinking

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

## Context = Setting That Changes Meaning

Context isn't just a namespace—it changes what words mean:

| Subdomain | What "Product" Means |
|-----------|----------------------|
| **Checkout** | SKU, name, description |
| **Billing** | SKU, quantity, cost per unit |
| **Fulfillment** | SKU, label, quantity on hand, warehouse |

> "The product you thought was a single concept is not the same across subdomains."

Each bounded context may have its OWN Product schema/table.

## Subdomains Have Dialects

Listen to domain experts. Same language, different dialects:

```
Checkout team:    "Customer selects products"
Billing team:     "We calculate line items"
Fulfillment team: "We ship packages"
```

Each group uses "product" differently → separate bounded contexts.

## Think Top-Down, Not Bottom-Up

**Wrong:** Entity → Context (database-driven design)
**Right:** Subdomain → Context → Entity

Stop asking "What context does Product belong to?"
Start asking "What is a Product in this business domain?"

## DDD Tactical Patterns as Tokenized Pipelines

Apply patterns like Plug conn or Ecto changeset:

```elixir
def create_product(params) do
  params
  |> Products.build()       # Factory: unstructured → domain
  |> Products.validate()    # Aggregate: enforce invariants
  |> Products.insert()      # Repository: persist
end
```

| Pattern | Elixir Equivalent |
|---------|-------------------|
| Entity | Schema with ID |
| Value Object | Embedded schema, struct |
| Aggregate | Module with transactional operations |
| Factory | `build/1` functions |
| Repository | `get/1`, `insert/1` wrappers |

## Express Domain Behaviors as Functions

Think in events → commands:

| Event (Past) | Command (Context Function) |
|--------------|----------------------------|
| Order form submitted | `Checkout.place_order/1` |
| Blog post created | `Social.notify_followers/1` |

> "Listen to the domain language. Express domain behaviors as functions."

## Composing Bounded Contexts with Events

Use events as data structures (not event sourcing machinery):

```elixir
def agent_joins_room(agent_id) do
  with {:ok, room} <- BackgroundCalls.get_available_room(),
       {:ok, event} <- BackgroundCalls.start_dialing_session(room, agent_id) do
    # Event struct passed to another bounded context
    TaskManagement.update_task(event)
  end
end
```

**Why events:** Minimal data shared, reduces coupling, contexts stay autonomous.

## Cross-Context References: IDs, Not Associations

```elixir
defmodule ShoppingCart.CartItem do
  schema "cart_items" do
    field :product_id, :integer  # Reference by ID
    # NOT: belongs_to :product, Catalog.Product
  end
end

# Query through the context
def get_cart_with_products(cart) do
  product_ids = Enum.map(cart.items, & &1.product_id)
  products = Catalog.list_products_by_ids(product_ids)
end
```

Keeps contexts independent and testable.

## Schema ≠ Database Table

Ecto schemas are Elixir representations—they don't have to map 1:1:

| Use Case | Approach |
|----------|----------|
| Database table | Standard `schema/2` |
| Form validation only | `embedded_schema/1` |
| API request/response | Embedded schema or schemaless |
| JSON column structure | `embeds_one/many` |

## Multiple Changesets per Schema

```elixir
def registration_changeset(user, attrs)  # Full validation + password
def profile_changeset(user, attrs)       # Name, bio only
def admin_changeset(user, attrs)         # Role, verified_at
```

Different operations = different changesets.

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

## Multi-Tenancy: Composite Foreign Keys

```elixir
create table(:comments) do
  add :org_id, :integer, null: false
  add :post_id, references(:posts, with: [org_id: :org_id], match: :full)
end
```

Use `prepare_query/3` for automatic scoping:

```elixir
def prepare_query(_operation, query, opts) do
  if org_id = opts[:org_id] do
    {from(q in query, where: q.org_id == ^org_id), opts}
  else
    raise "org_id is required"
  end
end
```

## CRUD Contexts Are Fine

> "If you have a CRUD bounded context, go for it. No need to add complexity."

Use generators for simple cases. Only add factory/aggregate/repository when business logic demands it.

## Preload vs Join Trade-offs

| Approach | Best For |
|----------|----------|
| Separate preloads | Has-many with many records (less memory) |
| Join preloads | Belongs-to, has-one (single query) |

Join preloads can use 10x more memory for has-many.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I'll query in mount, it's simpler" | mount is called twice. Use handle_params. |
| "This app is too small for contexts" | Contexts are about meaning, not size. |
| "I'll just use belongs_to across contexts" | Cross-context = IDs only. Keeps contexts independent. |
| "One schema per table is cleaner" | Multiple schemas per table is valid. Different views = different schemas. |
| "I don't need Scopes for this" | Scopes prevent OWASP #1. Use them. |
| "Preloading everything is easier" | Join preloads can use 10x memory. Think about it. |
| "PubSub topics don't need scoping" | Unscoped topics = data leaks. Always scope. |
| "LiveView can poll the external API" | One GenServer polls, broadcasts to all. Don't multiply requests. |
| "I'll add contexts later" | Refactoring contexts is painful. Design upfront. |
| "CRUD doesn't need DDD" | CRUD contexts are fine. DDD is optional complexity. |

## Red Flags - STOP and Reconsider

- Database query in mount/3
- belongs_to pointing to another context's schema
- Unscoped PubSub topics in multi-tenant app
- LiveView polling external APIs directly
- Single changeset for all operations
- Preloading has-many with join
- Skipping Scopes "for simplicity"

**Any of these? Re-read The Iron Law and the relevant section.**
