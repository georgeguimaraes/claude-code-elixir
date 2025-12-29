---
name: ecto-thinking
description: Use when writing Ecto code. Contains insights about Contexts, DDD patterns, schemas, changesets, and database gotchas from José Valim.
---

# Ecto Architectural Thinking

Mental shifts for Ecto and data layer design. These insights challenge typical ORM patterns.

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

## Gotchas from Core Team

Counterintuitive behaviors documented by José Valim.

### CTE Queries Don't Inherit Schema Prefix

In multi-tenant apps, CTEs don't get the parent query's prefix.

```elixir
# The CTE runs in wrong schema:
from(p in Product)
|> with_cte("tree", as: ^recursive_query)  # recursive_query has no prefix!
```

**Fix:** Explicitly set prefix: `%{recursive_query | prefix: "tenant"}`

### Mixed Keys Check Only Examines First 32 Keys

`Changeset.cast` mixed keys warning only checks first 32 keys. Atom keys after position 32 slip through.

```elixir
params = %{"k1" => 1, ..., "k32" => 32, key33: 33}  # No warning!
```

**Why:** Performance—full check appeared in profiling.

**Fix:** Sanitize params at controller boundary, not changeset.

### Embedded Schema "Loaded" vs Primary Key

Empty assocs/embeds populate based on whether struct is **loaded from DB**, not whether primary key exists.

```elixir
user = %User{id: 1}  # Manually set ID
put_assoc(user, :posts, [])  # Doesn't work as expected

user = Repo.get!(User, 1)  # Loaded from DB
put_assoc(user, :posts, [])  # Works - struct is "loaded"
```

**Fix:** Use `Repo.load/2` if you need a "loaded" struct without DB query.

### Repo.transact is Replacing transaction

`Repo.transaction` is being soft-deprecated. New `transact` only allows `{:ok, _}` or `{:error, _}` returns.

```elixir
# Old - ambiguous what triggers rollback:
Repo.transaction(fn ->
  :something  # Does this rollback? Who knows!
end)

# New - explicit:
Repo.transact(fn ->
  {:ok, result}  # or {:error, reason}
end)
```

Plan for this API change.

### preload_order for Association Sorting

Instead of sorting after fetch:

```elixir
schema "posts" do
  has_many :comments, Comment, preload_order: [desc: :inserted_at]
end
```

Note: Doesn't work for `through` associations—sort those after fetching.

### Parameterized Queries ≠ Prepared Statements

> "Those are separated things. One is parameterized queries the other is prepared statements."

- **Parameterized queries:** `SELECT * FROM users WHERE id = $1` — always used by Ecto
- **Prepared statements:** Query plan cached by name — can be disabled

**pgbouncer compatibility:** Use `prepare: :unnamed` (disables prepared statements, keeps parameterized queries).

### pool_count vs pool_size

More pools with fewer connections = better for benchmarks:

| pool_count | pool_size | ips |
|------------|-----------|-----|
| 1 | 32 | 1.53 K |
| 8 | 4 | 2.39 K |

**But:** With heterogeneous workflows (mix of fast/slow queries), a single larger pool gives better latency—you get "first available connection."

**Rule:** `pool_count` for uniform workloads (benchmarks), larger `pool_size` for real apps.

### Sandbox Mode Doesn't Work With External Processes

Cachex, separate GenServers, or anything outside the test process won't share the sandbox transaction.

> "If they need to be part of the same transaction, then you need to redesign the solution because they are not part of the same transaction in practice and the sandbox helped you find a bug."

**Fix:** Make the external service use the test process, or disable sandbox for those tests.

### Null Bytes Crash Postgres

PostgreSQL rejects null bytes even though they're valid UTF-8:

```elixir
Repo.insert(%User{name: "foo\x00bar"})  # Raises!
```

**Fix:** Sanitize at boundaries: `String.replace(string, "\x00", "")`

### Runtime Migrations Use List API

For migrations at runtime (not mix tasks):

```elixir
Ecto.Migrator.run(Repo, [{0, MyApp.Migration1}, {1, MyApp.Migration2}], :up, opts)
```

Keeps migrations as compiled code, avoids module recompilation warnings.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "This app is too small for contexts" | Contexts are about meaning, not size. |
| "I'll just use belongs_to across contexts" | Cross-context = IDs only. Keeps contexts independent. |
| "One schema per table is cleaner" | Multiple schemas per table is valid. Different views = different schemas. |
| "Preloading everything is easier" | Join preloads can use 10x memory. Think about it. |
| "I'll add contexts later" | Refactoring contexts is painful. Design upfront. |
| "CRUD doesn't need DDD" | CRUD contexts are fine. DDD is optional complexity. |

## Red Flags - STOP and Reconsider

- belongs_to pointing to another context's schema
- Single changeset for all operations
- Preloading has-many with join
- CTEs in multi-tenant apps without explicit prefix
- Trusting Changeset.cast mixed keys warning with 32+ keys
- Using pgbouncer without `prepare: :unnamed`
- Testing with Cachex/GenServers assuming sandbox shares transactions
- Accepting user input without null byte sanitization

**Any of these? Re-read the Gotchas section.**
