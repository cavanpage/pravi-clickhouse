# 07 · Data skipping indices

**Goal:** speed up filters on columns that *aren't* in your primary key, by
letting ClickHouse skip granules that can't match.

Docs: [Data skipping indices](https://clickhouse.com/docs/best-practices/use-data-skipping-indices-where-appropriate) ·
[Skip index reference](https://clickhouse.com/docs/optimize/skipping-indexes)

## The problem they solve

Your primary key can only optimize filters on its **leading columns** (lesson
01). But you also query other columns. A **data skipping index** is a secondary
index that stores a small summary per block of granules; if the summary proves
"no matching row can be here," ClickHouse skips reading that block.

They don't point *to* rows (that's an OLTP B-tree). They let ClickHouse **avoid
reading** blocks — same philosophy as the primary key, applied to other columns.

## The index types

Declared with `INDEX name expr TYPE ... GRANULARITY g`:

| Type | Stores per block | Best for |
|------|------------------|----------|
| `minmax` | min & max of the expression | numeric/date columns **correlated with the sort order** (e.g. a secondary timestamp) — the cheapest, try it first |
| `set(N)` | up to N distinct values | low-cardinality columns with clustered values; skips blocks not containing your value |
| `bloom_filter(p)` | a Bloom filter of values | equality/`IN` on higher-cardinality columns |
| `tokenbf_v1` / `ngrambf_v1` | Bloom filter of tokens/ngrams | substring/text search (`LIKE '%foo%'`, `hasToken`) |

`GRANULARITY g` = how many table granules each index block summarizes. Higher = a
smaller, coarser index.

## When they help — and when they don't

Skipping indices are only effective when the indexed values are **physically
clustered** on disk, so that whole blocks can be excluded. Their golden case is a
column **correlated with the primary key / insert order**.

If the values are uniformly scattered (every block contains every value), the
index can never skip anything — it just adds overhead. So:

- **Measure.** Compare `read_rows` with and without the index. If it didn't drop,
  the index isn't earning its keep.
- Prefer `minmax` first; it's tiny.
- Don't bloom-filter a near-unique high-cardinality column blindly.

## What you'll do in `lesson.sql`
Add a `minmax` index on `trip_distance` and a `set` index on `passenger_count`
to a copy of the trips table, then compare `read_rows` for the same filtered
query with the index materialized vs. not — proving (or disproving) its value.
