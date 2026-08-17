# PostgreSQL RLS, Transactions, and Tenant Context

_Last updated: 2026-08-17_

## What I learned

In a shared-schema multi-tenant SaaS, every tenant-owned row can carry a `tenant_id`:

```text
courses
┌────┬────────────┬───────────┐
│ id │ name       │ tenant_id │
├────┼────────────┼───────────┤
│ 1  │ Maths      │ VNR       │
│ 2  │ DS         │ VNR       │
│ 3  │ Physics    │ CBIT      │
│ 4  │ Chemistry  │ CBIT      │
└────┴────────────┴───────────┘
```

There are two broad ways to enforce tenant isolation:

### Application / ORM filtering

The application or ORM adds the tenant condition to every query:

```sql
SELECT * FROM courses
WHERE tenant_id = 'VNR';
```

ORM middleware can automate this, so developers do not have to hand-write the filter each time. However, the enforcement still lives in the application layer. A raw SQL path, another service, or a bug/bypass in the middleware can potentially escape the protection.

### PostgreSQL RLS

The application establishes the tenant context for the database transaction:

```sql
SET LOCAL app.tenant_id = 'VNR';
```

Then PostgreSQL's Row-Level Security policy enforces the boundary:

```sql
CREATE POLICY tenant_isolation ON courses
USING (tenant_id = current_setting('app.tenant_id')::text);
```

The application can now issue:

```sql
SELECT * FROM courses;
```

and PostgreSQL applies the tenant restriction through the RLS policy.

> **Mental model:** application filtering says "remember to filter the tenant"; RLS says "tell the database which tenant this transaction represents, and the database enforces the boundary." 

## `app.tenant_id` vs `tenant_id`

These are related but are **not the same thing**.

- `app.tenant_id` = transaction/request context established by the application: **"this transaction is acting on behalf of VNR."**
- `courses.tenant_id` = data stored on the row: **"this course belongs to VNR."**
- The RLS policy connects the two.

PostgreSQL does **not** inherently know that `Abhi → VNR`. The application authenticates Abhi, resolves his tenant, and establishes the tenant context. PostgreSQL then enforces the policy using that context.

```text
Abhi
  │
  │ authentication / tenant lookup
  ↓
Abhi → VNR
  │
  │ SET LOCAL app.tenant_id = 'VNR'
  ↓
PostgreSQL transaction
  │
  ↓
RLS policy
  │
  ↓
row.tenant_id must match VNR
```

## Why the tenant context is transaction-scoped

Suppose one HTTP request needs three database operations:

```text
HTTP request
   ↓
BEGIN
   ↓
SET LOCAL tenant = VNR
   ↓
Query 1
   ↓
Query 2
   ↓
Query 3
   ↓
COMMIT
```

The tenant context is established **once for the transaction**, not before every query.

`SET LOCAL` is useful with connection pooling because the physical database connection does not permanently become a VNR connection. After the transaction ends, the connection can return to the pool and later serve another tenant.

Conceptually:

```text
Connection #17

Request A
  BEGIN
  tenant = VNR
  queries...
  COMMIT
       ↓
connection returns to pool
       ↓
Request B
  BEGIN
  tenant = CBIT
  queries...
  COMMIT
```

Thousands of SaaS users therefore do **not** require thousands of database connections.

```text
10,000 users
      ↓
HTTP requests
      ↓
A few API servers
      ↓
Connection pool
      ↓
A much smaller number of DB connections
```

## Does every query become a transaction?

A single SQL statement executes within a database transaction even when the application does not explicitly issue `BEGIN`/`COMMIT` (an implicit transaction).

However, if tenant context is established with `SET LOCAL`, the context-setting statement and the protected query need to share an explicit transaction scope. An ORM can hide this transaction management from the application code.

So the useful mental model is:

> **RLS does not require a manually written transaction around every query. But if the RLS policy depends on transaction-local tenant context, the context and the queries using it must live inside the same transaction.**

## Why RLS is stronger than automatic ORM filtering

An ORM middleware can make this:

```sql
SELECT * FROM courses WHERE tenant_id = 'VNR';
```

happen automatically. Functionally, that can look almost identical to RLS.

The difference is the **security boundary**:

```text
ORM middleware
    ↓
application-level enforcement
    ↓
can potentially be bypassed by another data-access path
```

versus:

```text
Application establishes tenant context
    ↓
PostgreSQL RLS
    ↓
database-level enforcement
    ↓
protected table operations are subject to the policy
```

A strong architecture can use both: ORM-level scoping for developer ergonomics and PostgreSQL RLS as the database-level backstop.

### The order to adopt them in

They are two *independent* controls, which is what defence in depth actually requires — a wrapper plus a convention is one control wearing two hats. But they are not equal effort:

| | ORM / client extension | RLS |
|---|---|---|
| Enforcement point | application | database engine |
| Covers raw SQL, other services, `psql` | ❌ | ✅ |
| Debuggable in application code | ✅ | ❌ — the filter is invisible |
| Works outside a transaction | ✅ | ❌ |
| Needs a least-privileged DB role | ❌ | ✅ |
| Sensitive to pooler mode | ❌ | ✅ |
| Effort to adopt | ~a day | weeks, plus an operational change |

```text
1. ORM / client-extension scoping      cheap, debuggable, covers nearly every query at once
2. least-privileged runtime role       the prerequisite most teams skip — see below
3. transaction discipline              a helper that guarantees the context is set
4. RLS on the highest-value tables     then broaden, with the CI check below
```

The extension protects the paths you remembered. RLS protects the paths you did not think of. Shipping only the second is slow; shipping only the first leaves raw SQL and future services unguarded.

## `USING` vs `WITH CHECK` — the half-finished policy

The policy above only has a `USING` clause. That protects **reads**, not **writes**.

```sql
CREATE POLICY tenant_isolation ON courses
  USING      (tenant_id = current_setting('app.tenant_id', true))   -- READS
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true));  -- WRITES
```

| Clause | Governs | If omitted |
|---|---|---|
| `USING` | which rows are visible, and which rows `UPDATE`/`DELETE` may *touch* | nothing is filtered |
| `WITH CHECK` | which rows may be *created or written* | a tenant can insert a row belonging to another tenant, or move a row **into** another tenant |

`USING` never examines new row values — it only filters existing rows. So with `USING` alone, while the session is VNR:

```sql
INSERT INTO courses (id, tenant_id, name) VALUES ('c1', 'CBIT', 'x');   -- allowed
UPDATE courses SET tenant_id = 'CBIT' WHERE id = 'c2';                  -- allowed
```

> **Write the pair together, always.** If they genuinely should differ — read a shared catalogue, write only your own rows — make that asymmetry explicit and comment why.

## The fail-closed property, and the two ways people destroy it

Note the second argument in the policy just above — `current_setting('app.tenant_id', true)`. The earlier example in "What I learned" omits it, and the difference matters. The `true` is `missing_ok`: it returns **NULL** when the variable is unset instead of raising an error. Combined with an equality test:

```text
context unset  →  current_setting(...) = NULL  →  tenant_id = NULL is never true  →  ZERO rows
```

**Zero rows, not all rows.** A forgotten `SET LOCAL` becomes an empty result, not a full-table leak. That single property is what makes RLS safe, and it is easy to remove while trying to make local development convenient:

```sql
-- ❌ NULL context now sees EVERYTHING
USING (tenant_id = current_setting('app.tenant_id', true)
       OR current_setting('app.tenant_id', true) IS NULL)

-- ❌ the same mistake wearing a COALESCE
USING (tenant_id = COALESCE(current_setting('app.tenant_id', true), tenant_id))
```

Both convert "no context" from *deny everything* to *allow everything*. **Add a test asserting that a query with no context returns zero rows** — that test is the guard on the guard.

Without `missing_ok`, an unset variable *errors* instead. That is arguably safer, but it makes every query fail rather than only leaking-relevant ones; NULL plus a fail-closed comparison is the usual choice.

## Why "RLS is enabled" often means "RLS is enforcing nothing"

RLS has documented bypasses, and the most common production mistake is enabling policies while the application still connects as a role that ignores them.

| Bypass | Detail |
|---|---|
| **Table owner** | by default, the owner of a table is **not** subject to its own policies |
| **`BYPASSRLS` attribute** | roles granted it, and superusers, ignore every policy |
| **`FORCE ROW LEVEL SECURITY` unset** | required to apply policies to the table owner as well |

```sql
ALTER TABLE courses FORCE ROW LEVEL SECURITY;   -- apply policies even to the owner

CREATE ROLE app_runtime LOGIN PASSWORD '...';   -- not the owner, not superuser, no BYPASSRLS
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_runtime;
```

> **If the application connects as the schema owner or a superuser — the default in most setups — turning on RLS changes nothing.** Moving the runtime connection to a least-privileged role *is* the work; writing policies is the easy part.

Migrations are the deliberate exception: schema tooling should connect as an elevated role. That means **two connection strings**, one for the app and one for migrations — a deployment change, not just a code change.

## Policies are schema, so absence is silent

`ENABLE ROW LEVEL SECURITY` is per table. A new table has no policy and no protection, and nothing announces it.

```sql
-- every table with a tenant column should have RLS enabled and at least one policy
SELECT c.relname
FROM pg_class c
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'tenant_id'
WHERE c.relkind = 'r'
  AND (NOT c.relrowsecurity
       OR NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.tablename = c.relname));
```

Run it in CI and fail the build on any row. Otherwise "add RLS to new tables" is a convention, and conventions without tooling are wishes.

## What debugging costs

RLS makes the filter **invisible in application code**. The symptom table is worth memorising, because every entry looks like a different bug:

| Symptom | Actual cause |
|---|---|
| "My query returns nothing" | context unset, or set outside the transaction |
| "Works in a script, not in the app" | the script connects as owner; the app doesn't |
| "Works in tests, not in production" | tests set the context; one production path doesn't |
| "This query got slower" | the policy predicate is now in every plan |

Two habits make it tolerable: a **helper that wraps every tenant-scoped operation** and issues `SET LOCAL` as its first statement — so querying outside a transaction is impossible — and a non-production debug endpoint reporting `current_setting('app.tenant_id', true)`, so "is the context set?" is answerable in one call instead of by inference.

Index design changes too: the tenant predicate joins every query, so composite indexes should lead with the tenant column — `(tenant_id, created_at)` rather than `(created_at)`.

## Poolers: `SET LOCAL` is safe, plain `SET` is not

The pooling discussion above assumes the pool hands out whole connections. A **transaction-mode pooler** (PgBouncer in `transaction` mode, and equivalents) multiplexes one backend across concurrent transactions.

```text
session-mode pooler       → one connection per client session   → SET and SET LOCAL both work
transaction-mode pooler   → connection reassigned per transaction
                              SET LOCAL inside an explicit transaction  → safe
                              plain SET                                  → NOT safe at all
```

Know which mode sits in front of the database before relying on session state. This is the difference between "worked in staging" and "leaked under load".

## CockroachDB

CockroachDB supports RLS — see the [Row-Level Security overview](https://www.cockroachlabs.com/docs/v26.2/row-level-security). Policies are boolean expressions evaluated per statement against the current user, as in PostgreSQL, so everything above transfers.

Two caveats: **verify behaviour for your cluster version** — parts of the implementation have matured over time, with `WITH CHECK` handling and `security_invoker` on views both having had open work upstream — and with an ORM over a `pg`-style pool, the safe pattern is `SET LOCAL` as the **first statement inside** the ORM's transaction primitive. Setting it outside leaves it on a pooled connection the next request may reuse.

## RLS does not mean one PostgreSQL role per SaaS user

A common misconception is that PostgreSQL needs a separate role for every application user.

It does not.

```text
Application identity:
Abhi → VNR → Professor

PostgreSQL identity:
app_user
```

Thousands of application users can share one or a few PostgreSQL roles. Application authorization decides what Abhi is allowed to do; RLS can enforce which tenant rows the database operation can access.

## Connection to transactions

Transactions are a general relational-database concept, not an RLS concept.

A transaction groups database operations into one logical unit of work. If a transaction is rolled back, changes made within it are undone. This is the **atomicity** part of ACID.

```text
BEGIN
  ↓
Operation 1
  ↓
Operation 2
  ↓
Operation 3
  ↓
COMMIT  → all changes persist

Failure + ROLLBACK → changes from the transaction are undone
```

RLS is simply using the transaction boundary for an additional purpose: safely scoping the tenant context.

## The overall mental model

```text
                         USER
                          │
                          ↓
                    HTTP request
                          │
                          ↓
                 Authenticate user
                          │
                          ↓
               Resolve tenant: VNR
                          │
                          ↓
                DB connection pool
                          │
                          ↓
                      BEGIN
                          │
                          ↓
             SET LOCAL tenant = VNR
                          │
                          ↓
                 Multiple queries
                          │
                          ↓
                 PostgreSQL RLS
                          │
                          ↓
              Only VNR rows allowed
                          │
                          ↓
                COMMIT / ROLLBACK
                          │
                          ↓
                connection → pool
```

## Key takeaway

> **The application still has to tell PostgreSQL which tenant the transaction represents. RLS does not discover the tenant; it enforces the tenant boundary once the application establishes that context.**

The big architectural difference is **who guarantees the filter**:

- Application/ORM: *the application guarantees the tenant filter is added.*
- RLS: *PostgreSQL guarantees the policy is applied to the protected table.*

---

## Related concepts

- Multi-tenancy isolation models → `multi-tenancy.md`
- PostgreSQL schemas and tables
- Database transactions and ACID
- Connection pooling
- Authentication and tenant resolution
- Application authorization / RBAC
- ORM middleware and repository patterns
