# 03 · Materialized views

**Goal:** pre-compute expensive aggregations so dashboard queries are instant,
using ClickHouse's two kinds of materialized view.

Docs: [Use materialized views](https://clickhouse.com/docs/best-practices/use-materialized-views) ·
[Incremental MVs](https://clickhouse.com/docs/materialized-view/incremental-materialized-view) ·
[Refreshable MVs](https://clickhouse.com/docs/materialized-view/refreshable-materialized-view)

## A ClickHouse materialized view is a trigger, not a snapshot

This trips up everyone coming from Postgres. An **incremental** materialized view
is not a cached result set. It's an **insert trigger**: when rows land in the
*source* table, ClickHouse runs the view's `SELECT` over *just that new block*
and writes the result into a separate *target* table. The cost is paid at insert
time, on new data only — reads then hit a tiny pre-aggregated table.

```
INSERT into source ──▶ MV's SELECT runs on the new block ──▶ rows appended to target
```

Key consequences:
- The MV only sees data inserted **after** it's created. Backfill the target
  table manually for existing data (the `lesson.sql` shows how).
- The target table is a normal table you can query directly and fast.

## Aggregating correctly: -State / -Merge

You can't just store `avg()` per insert block and add the results later —
averages don't sum. ClickHouse solves this with **aggregate function states**:

- In the MV, compute partial **states** with the `-State` suffix:
  `avgState(x)`, `sumState(x)`, `uniqState(x)`.
- Store them in an **`AggregatingMergeTree`** target table, where columns are
  `AggregateFunction(avg, Float64)` etc. Background merges combine states for
  the same key automatically.
- At read time, finalize with the `-Merge` suffix: `avgMerge(state)`.

For plain additive counters, **`SummingMergeTree`** is a simpler option: it just
sums numeric columns sharing the same sorting key.

## The other kind: refreshable materialized views

A **refreshable** MV is the classic OLTP-style snapshot: it re-runs the *whole*
query on a schedule (`REFRESH EVERY 1 HOUR`) and replaces (or appends to) the
target. Use it when:
- The query has complex multi-table JOINs that don't fit the per-block model.
- You want a "top N" / lookup table that's small and can be slightly stale.
- The result set size is bounded (it won't grow forever).

Incremental = real-time, unbounded scale, single-table transforms.
Refreshable = periodic, complex queries, bounded results, staleness OK.

## What you'll do in `lesson.sql`

Build an incremental MV that maintains per-neighbourhood, per-day trip stats with
`AggregatingMergeTree`, backfill it, insert new rows to watch it update live,
then build a refreshable "top neighbourhoods" view for comparison.
