# 01 · Primary keys & ORDER BY

**Goal:** understand ClickHouse's *sparse* primary key and choose an `ORDER BY`
that makes your queries read orders of magnitude less data.

Docs: [Choosing a primary key](https://clickhouse.com/docs/best-practices/choosing-a-primary-key) ·
[Primary indexes deep dive](https://clickhouse.com/docs/guides/best-practices/sparse-primary-indexes)

## A primary key is not what you think

In Postgres/MySQL, a primary key is a unique constraint backed by a B-tree with
one entry per row. **ClickHouse's primary key is neither unique nor per-row.**

ClickHouse sorts the whole table on disk by the `ORDER BY` columns, splits it
into **granules** of (by default) 8192 rows, and stores *one* index entry per
granule — the value of the key columns at the start of that granule. This is a
**sparse index**: tiny (millions of rows → thousands of marks), so it lives in
memory.

When you filter on key columns, ClickHouse uses the sparse index to skip whole
granules that can't contain matching rows, then reads only the survivors. The
scoreboard for "did it work?" is **`read_rows`**: a good key makes it a small
fraction of the table.

> `PRIMARY KEY` and `ORDER BY` are usually the same thing. If you only write
> `ORDER BY`, it *is* the primary key. (You can make the primary key a prefix of
> `ORDER BY` for special cases, but start with them equal.)

## How to choose the columns (in priority order)

From the official guidance — apply these in order; they sometimes conflict:

1. **Filter columns first.** Put columns that appear in `WHERE` and eliminate
   the most rows. A key only helps queries that filter on its leading columns.
2. **Leading columns should be low-cardinality.** Order from fewest distinct
   values to most. Low-cardinality-first keeps granules "pure" and compresses
   better. (e.g. `(event_type, timestamp)`, not `(timestamp, event_type)`.)
3. **Pick a sensible granularity.** Indexing `toDate(ts)` instead of a
   full-second `DateTime` shrinks the index and is usually enough.
4. **4–5 columns is plenty.** Each extra column helps fewer queries and costs
   sort/compression effort.

## The catch

The `ORDER BY` is **fixed at table creation** — you can't add or reorder key
columns later. (Projections and skipping indices, lessons 07, let you add
alternative access paths afterward, at the cost of duplication.) So this is the
one decision worth getting right up front.

## What you'll do in `lesson.sql`

Build two copies of a taxi-trips table with different `ORDER BY` choices, run the
same neighbourhood query against both, and compare `read_rows`. The well-chosen
key reads a tiny slice; the poorly-chosen one scans almost everything.
