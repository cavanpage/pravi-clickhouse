# 09 · Avoid OPTIMIZE FINAL

**Goal:** understand how merges work, why people reach for `OPTIMIZE TABLE ...
FINAL`, why it usually hurts, and what to do instead.

Docs: [Avoid OPTIMIZE FINAL](https://clickhouse.com/docs/best-practices/avoid-optimize-final) ·
[OPTIMIZE](https://clickhouse.com/docs/sql-reference/statements/optimize)

## How merges actually work

Every insert writes a new **part**. A background process continuously **merges**
small parts into bigger ones — sorting, applying `ReplacingMergeTree`/
`SummingMergeTree` collapsing, and removing lightweight-deleted rows along the
way. This is automatic, incremental, and tuned to not overwhelm the system.

Crucially, ClickHouse **does not guarantee everything merges into one part**.
It merges when it's worthwhile, up to size limits. That's by design — fully
merging huge tables is rarely worth the cost.

## What `OPTIMIZE FINAL` does and why it's a trap

`OPTIMIZE TABLE t FINAL` forces ClickHouse to merge **all** parts of (each
partition of) the table into a **single** part right now, regardless of whether
that's economical.

- It **re-reads and re-writes the entire table** — potentially terabytes — in
  one shot. Massive, sustained I/O and CPU.
- It competes with normal merges and inserts and can stall ingestion.
- The benefit is usually **temporary**: the next inserts create new parts again.

So running `OPTIMIZE FINAL` on a schedule (or reflexively after a load) is a
classic anti-pattern. The background merge process already does this work,
proportionally and out of your way.

## "But I need deduplicated results from my ReplacingMergeTree!"

That's the real need behind most `OPTIMIZE FINAL` usage. The answer is the
**`FINAL` modifier on the query**, not `OPTIMIZE`:

```sql
SELECT * FROM users FINAL;          -- dedup/collapse at read time, no rewrite
```

`SELECT ... FINAL` merges the relevant rows **on the fly for that query only**.
It has a cost (extra work per read), but it's bounded to what you read and
doesn't rewrite your whole table. Often you can avoid even that by aggregating
away the duplicates (`argMax(col, version)`, `GROUP BY id`).

## When is `OPTIMIZE` legitimately OK?
- A **one-off**, manual compaction after a big historical backfill, during a
  quiet window — not on a schedule.
- `OPTIMIZE ... DEDUPLICATE` for a deliberate, occasional cleanup.

If you find yourself scripting `OPTIMIZE FINAL`, step back: you probably want
`SELECT ... FINAL`, an `AggregatingMergeTree`, or read-time aggregation instead.

## What you'll do in `lesson.sql`
Create duplicates in a `ReplacingMergeTree`, get correct results three ways
(`FINAL` query, `argMax` aggregation, and — for contrast — `OPTIMIZE FINAL`),
and compare the cost of each.
