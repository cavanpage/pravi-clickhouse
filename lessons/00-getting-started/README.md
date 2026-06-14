# 00 · Getting started

**Goal:** get comfortable creating a table, inserting data, querying it, and —
most importantly — *seeing what ClickHouse actually did*.

Docs: [Quick start](https://clickhouse.com/docs/getting-started/quick-start) ·
[MergeTree engine](https://clickhouse.com/docs/engines/table-engines/mergetree-family/mergetree)

## The one idea that matters

ClickHouse is a **column-oriented** OLAP database. Where a row store (Postgres,
MySQL) keeps each row's columns together on disk, ClickHouse stores each *column*
together. A query like `SELECT avg(fare_amount) FROM trips` only reads the
`fare_amount` column and ignores the other 16 — that's why it can scan hundreds
of millions of rows in milliseconds.

This single fact explains almost every best practice in this course:

- **Compression is huge** because a column holds similar values next to each
  other (lesson 02).
- **Reading less data is the whole game** — the primary key, partitioning, and
  skipping indices all exist to avoid reading columns you don't need (lessons
  01, 05, 07).
- **Wide tables are fine.** Adding columns you rarely select costs almost
  nothing because they're never read unless asked for.

## The default table engine: MergeTree

Almost every table you create uses the **MergeTree** engine or one of its
variants. Inserts create immutable, sorted "parts" on disk; a background process
merges small parts into bigger ones over time (hence the name). You'll see the
consequences of this design throughout the course — especially in lessons 06
(inserts), 08 (mutations), and 09 (merges).

## Seeing what happened

Two tools you'll use in every lesson:

- **`EXPLAIN indexes = 1 SELECT ...`** — shows which granules the primary key
  lets ClickHouse skip *before* it runs.
- **`system.query_log`** — after a query runs, it records `read_rows`,
  `read_bytes`, and timing. The lessons query this to prove that an optimization
  worked.

Run `lesson.sql` to walk through all of it.
