# 08 · Avoid mutations

**Goal:** stop thinking in `UPDATE`/`DELETE`. Learn the insert-oriented patterns
ClickHouse is built for, and the lighter-weight tools for when you truly must
change data.

Docs: [Avoid mutations](https://clickhouse.com/docs/best-practices/avoid-mutations) ·
[ReplacingMergeTree](https://clickhouse.com/docs/engines/table-engines/mergetree-family/replacingmergetree) ·
[Lightweight DELETE](https://clickhouse.com/docs/sql-reference/statements/delete)

## Why `ALTER ... UPDATE/DELETE` is expensive

In ClickHouse these are **mutations**. Parts are immutable, so a mutation
**rewrites every affected part from scratch** in the background. Update one row
in a billion-row part and ClickHouse rewrites the whole part. Mutations are:

- **Asynchronous** — the statement returns immediately; the work happens later
  (watch `system.mutations`).
- **Heavy on I/O** — they re-read and re-write data and compete with merges.
- **Not transactional** in the OLTP sense.

They exist for occasional bulk corrections (GDPR deletes, a backfill fix), not
for routine row-level churn. If your design needs frequent updates, the design —
not the update — is the problem.

## The patterns to use instead

### 1. Insert-only / append + aggregate at read time
Don't update a running total — insert events and `sum()` them when you read (or
maintain an `AggregatingMergeTree` via a materialized view, lesson 03). The
latest state is "the newest row," not "the mutated row."

### 2. `ReplacingMergeTree` for "keep the latest version"
Give the engine a sorting key (the entity id) and a version column. You just
**insert** new versions; background merges keep the row with the highest version
and drop the rest. Querying with `FINAL` (lesson 09) gives the deduplicated view
on demand.

```sql
CREATE TABLE users (id UInt64, name String, updated_at DateTime)
ENGINE = ReplacingMergeTree(updated_at)   -- version column
ORDER BY id;
-- "update" = insert a new row with a newer updated_at
```

### 3. Soft deletes
Add an `is_deleted UInt8` column, insert a tombstone, and filter
`WHERE is_deleted = 0` at read time (or via a `ReplacingMergeTree(version,
is_deleted)` which can physically drop them on merge). No part rewrite.

### 4. Lightweight `DELETE` when you must delete
`DELETE FROM t WHERE ...` is the modern, much cheaper alternative to `ALTER ...
DELETE`: it marks rows deleted with an internal mask and excludes them from
reads immediately, with the physical cleanup deferred to merges. Still not free —
use for occasional deletes, not a per-request workload.

## Rule of thumb
**Inserts are cheap; rewrites are expensive.** Model changes as new rows and
resolve them at read time. Reach for mutations only for rare, bulk, one-off
corrections.

## What you'll do in `lesson.sql`
Build a `ReplacingMergeTree`, "update" rows by inserting new versions, see the
duplicates collapse with `FINAL`, do a soft delete, and watch a real `ALTER
UPDATE` mutation appear in `system.mutations`.
