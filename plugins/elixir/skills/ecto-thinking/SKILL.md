---
name: ecto-thinking
description: Use when writing Ecto code. Contains insights about Contexts, DDD patterns, schemas, changesets, and database gotchas from José Valim.
---

# Ecto Thinking

Mental shifts for Ecto and data layer design. These insights challenge typical ORM patterns.

## Context = Setting That Changes Meaning

Context isn't just a namespace—it changes what words mean. "Product" means different things in Checkout (SKU, name), Billing (SKU, cost), and Fulfillment (SKU, warehouse). Each bounded context may have its OWN Product schema/table.

**Think top-down:** Subdomain → Context → Entity. Not "What context does Product belong to?" but "What is a Product in this business domain?"

## Cross-Context References: IDs, Not Associations

```elixir
schema "cart_items" do
  field :product_id, :integer  # Reference by ID
  # NOT: belongs_to :product, Catalog.Product
end
```

Query through the context, not across associations. Keeps contexts independent and testable.

## DDD Patterns as Pipelines

```elixir
def create_product(params) do
  params
  |> Products.build()       # Factory: unstructured → domain
  |> Products.validate()    # Aggregate: enforce invariants
  |> Products.insert()      # Repository: persist
end
```

Use events (as data structs) to compose bounded contexts with minimal coupling.

## Schema ≠ Database Table

| Use Case | Approach |
|----------|----------|
| Database table | Standard `schema/2` |
| Form validation only | `embedded_schema/1` |
| API request/response | Embedded schema or schemaless |

## Multiple Changesets per Schema

```elixir
def registration_changeset(user, attrs)  # Full validation + password
def profile_changeset(user, attrs)       # Name, bio only
def admin_changeset(user, attrs)         # Role, verified_at
```

Different operations = different changesets.

## Multi-Tenancy: Composite Foreign Keys

```elixir
add :post_id, references(:posts, with: [org_id: :org_id], match: :full)
```

Use `prepare_query/3` for automatic scoping. Raise if `org_id` missing.

## Preload vs Join Trade-offs

| Approach | Best For |
|----------|----------|
| Separate preloads | Has-many with many records (less memory) |
| Join preloads | Belongs-to, has-one (single query) |

Join preloads can use 10x more memory for has-many.

## CRUD Contexts Are Fine

> "If you have a CRUD bounded context, go for it. No need to add complexity."

Use generators for simple cases. Add DDD patterns only when business logic demands it.

## Gotchas from Core Team

### CTE Queries Don't Inherit Schema Prefix

In multi-tenant apps, CTEs don't get the parent query's prefix.

**Fix:** Explicitly set prefix: `%{recursive_query | prefix: "tenant"}`

### Parameterized Queries ≠ Prepared Statements

- **Parameterized queries:** `WHERE id = $1` — always used by Ecto
- **Prepared statements:** Query plan cached by name — can be disabled

**pgbouncer:** Use `prepare: :unnamed` (disables prepared statements, keeps parameterized queries).

### pool_count vs pool_size

More pools with fewer connections = better for benchmarks. **But** with mixed fast/slow queries, a single larger pool gives better latency.

**Rule:** `pool_count` for uniform workloads, larger `pool_size` for real apps.

### Sandbox Mode Doesn't Work With External Processes

Cachex, separate GenServers, or anything outside the test process won't share the sandbox transaction.

**Fix:** Make the external service use the test process, or accept it's not in the same transaction.

### Null Bytes Crash Postgres

PostgreSQL rejects null bytes even though they're valid UTF-8.

**Fix:** Sanitize at boundaries: `String.replace(string, "\x00", "")`

### preload_order for Association Sorting

```elixir
has_many :comments, Comment, preload_order: [desc: :inserted_at]
```

Note: Doesn't work for `through` associations.

### Runtime Migrations Use List API

```elixir
Ecto.Migrator.run(Repo, [{0, Migration1}, {1, Migration2}], :up, opts)
```

## Red Flags - STOP and Reconsider

- belongs_to pointing to another context's schema
- Single changeset for all operations
- Preloading has-many with join
- CTEs in multi-tenant apps without explicit prefix
- Using pgbouncer without `prepare: :unnamed`
- Testing with Cachex/GenServers assuming sandbox shares transactions
- Accepting user input without null byte sanitization

**Any of these? Re-read the Gotchas section.**
