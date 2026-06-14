# 05 · Partitioning

**Goal:** use `PARTITION BY` for cheap data management and pruning — without
falling into the classic over-partitioning trap.

Docs: [Choosing a partitioning key](https://clickhouse.com/docs/best-practices/choosing-a-partitioning-key) ·
[Custom partitioning](https://clickhouse.com/docs/engines/table-engines/mergetree-family/custom-partitioning-key) ·
[TTL](https://clickhouse.com/docs/guides/developer/ttl)

## Partitioning is not the primary key

These do different jobs and people constantly conflate them:

- **`ORDER BY` (primary key)** — sorts rows *within* a part and builds the sparse
  index. This is your main tool for fast filtered reads (lesson 01).
- **`PARTITION BY`** — physically splits the table into separate directories of
  parts, one group per partition value. Parts from different partitions are
  **never merged together**.

Partitioning's main wins are **data management**, with query pruning as a bonus:

1. **Instant drops.** `ALTER TABLE ... DROP PARTITION '202601'` deletes a
   month's data by unlinking files — effectively free, no mutation. This is the
   single best reason to partition.
2. **Partition pruning.** A query filtering on the partition expression skips
   whole partitions before the primary key even gets involved.
3. **Tiered storage / TTL.** Move or delete old partitions on a schedule.

## The golden rule: keep partitions coarse

The most common ClickHouse mistake is partitioning too finely. **Partition by
month, not by day or hour, for typical time-series.** Each partition holds
parts; thousands of tiny partitions means tons of small parts, slow merges,
bloated metadata, and "too many parts" insert errors.

Rule of thumb: aim for a manageable number of partitions (tens to low hundreds),
each holding a meaningful amount of data. `PARTITION BY toYYYYMM(ts)` is the
canonical choice. Avoid high-cardinality partition keys (user_id, full
timestamps).

> Partitioning is optional. If you don't need cheap drops or pruning by a coarse
> key, a single-partition table with a good `ORDER BY` is often best.

## TTL: let old data expire itself

`TTL` rules on a MergeTree table let ClickHouse delete or move rows/partitions
automatically once a time column passes a threshold — ideal for logs/metrics with
a retention window. It plays naturally with monthly partitions: whole partitions
age out and drop cheaply.

## What you'll do in `lesson.sql`
Create a monthly-partitioned trips table, watch partition pruning in `EXPLAIN`,
drop a whole month instantly, see why daily partitioning is a bad idea, and add a
TTL retention rule.
