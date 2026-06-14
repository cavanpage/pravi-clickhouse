# 04 · JOINs

**Goal:** join efficiently — and know when *not* to join at all.

Docs: [Minimize and optimize JOINs](https://clickhouse.com/docs/best-practices/minimize-optimize-joins) ·
[JOIN algorithms](https://clickhouse.com/docs/guides/joining-tables) ·
[Dictionaries](https://clickhouse.com/docs/dictionary)

## ClickHouse can join — but it's an OLAP engine

ClickHouse joins work and are fast, but the engine is built around scanning wide,
denormalized tables. Two habits keep joins cheap:

### 1. Put the smaller table on the right
For the default hash join, ClickHouse builds an in-memory hash table from the
**right**-hand table and streams the left table past it. So the right side should
be the *smaller* one. `big JOIN small` good; `small JOIN big` wastes memory.

```sql
SELECT ...
FROM trips           AS t        -- large, streamed
JOIN neighbourhoods  AS n        -- small, loaded into memory
    ON t.pickup_ntaname = n.name
```

### 2. Know the algorithms (and let ClickHouse pick)
Set via `join_algorithm`. The useful ones:
- **`hash`** (default) — right table in memory. Fast when the right side fits.
- **`parallel_hash`** — multi-threaded hash; faster on big right sides with RAM.
- **`grace_hash`** — spills to disk; use when the right side doesn't fit memory.
- **`full_sorting_merge`** — sorts both sides; good when inputs are already
  sorted or huge.
- **`direct`** — for joining against a key-value **dictionary** / table engine;
  no hash build, direct lookups.

`join_algorithm = 'auto'` lets ClickHouse choose and fall back as needed.

## Often the best join is a dictionary

For small, relatively static lookup data (id → name, code → label), a
**dictionary** beats a JOIN. ClickHouse loads it into memory (optionally
in-RAM-only) and you look values up with `dictGet()`:

```sql
SELECT dictGet('nta_dict', 'borough', pickup_ntaname) AS borough, count()
FROM trips GROUP BY borough;
```

No join, no hash build per query — just an in-memory lookup. Dictionaries can
refresh from a source table, file, or external DB on a schedule.

## And sometimes: don't join, denormalize
The most ClickHouse-y move is to fold lookup attributes into the fact table at
insert time (or via a materialized view), so reads need no join at all. Storage
is cheap; repeated join work at query time is not.

## What you'll do in `lesson.sql`
Build a small `neighbourhoods` dimension, join it to `trips` (correct side
first), compare a wrong-side join, then replace the join entirely with a
dictionary + `dictGet()`.
