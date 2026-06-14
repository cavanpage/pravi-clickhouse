# 06 · Insert strategy

**Goal:** ingest data fast and safely — big batches by default, async inserts
when you can't batch, and idempotent retries so you never double-count.

Docs: [Selecting an insert strategy](https://clickhouse.com/docs/best-practices/selecting-an-insert-strategy) ·
[Async inserts](https://clickhouse.com/docs/optimize/asynchronous-inserts)

## The #1 rule: insert in big batches

Every `INSERT` creates a **part** (a small sorted table on disk) that background
merges then have to combine. Many tiny inserts = a flood of tiny parts =
merge pressure and the dreaded **"too many parts"** error.

So:
- **Batch 10,000–100,000 rows per insert** (at least ~1,000).
- Aim for **roughly one insert per second**, not thousands.
- Do the batching **client-side** when you control the producer.

This one habit matters more for ingestion performance than anything else.

## When you can't batch: async inserts

Sometimes you have hundreds of agents each sending a few rows (observability,
IoT, edge). Client-side batching isn't feasible. Turn on **asynchronous
inserts**: the *server* buffers incoming rows and flushes a real part when a
threshold is hit:

- buffer reaches ~**100 MiB**, or
- ~**200 ms** elapses (1000 ms on Cloud), or
- ~**450** queued insert queries accumulate.

Enable it:
```sql
-- per query
INSERT INTO t SETTINGS async_insert = 1, wait_for_async_insert = 1 VALUES ...
-- or per user
ALTER USER learner SETTINGS async_insert = 1;
```

`wait_for_async_insert = 1` (recommended) makes the call return only once the
data is durably flushed — you trade a little latency for a real durability
guarantee. With `= 0` you get an ack as soon as it's buffered (faster, weaker
guarantee).

> Rule of thumb: **batch client-side if you can; use async inserts if you can't.**

## Idempotent retries (don't double-count)

Networks fail mid-insert. ClickHouse makes **synchronous inserts idempotent**:
it hashes each inserted block, and a re-insert of an *identical* block (same
rows, same order) is recognized as a duplicate and ignored. So the safe retry
recipe is:

- Retry the **exact same batch** — same contents, **same order**.
- Don't shuffle, split, or add rows on retry, or the hash changes and you get
  duplicates.

Note: block deduplication is **on by default for Replicated tables** (via
`replicated_deduplication_window`) but **off by default for a plain
single-node MergeTree** — enable it there with
`SETTINGS non_replicated_deduplication_window = N` (the lesson does this).
Async inserts have their own deduplication, controllable via
`async_insert_deduplicate`.

## Native vs HTTP

- **Native protocol** (port 9000; Go/Python/Java drivers) — fastest, columnar,
  compressed. Default for high-throughput ingestion.
- **HTTP** (port 8123; `clickhouse-connect`, curl) — most compatible and
  load-balancer-friendly, supports any input format (JSON, CSV, Parquet),
  marginally slower. Great default for apps and for ClickHouse Cloud.

## What you'll do
`lesson.sql` shows batch vs async insert syntax and how to inspect parts.
`example.py` is the real demo: it benchmarks **many tiny inserts** vs **one big
batch** vs **async inserts**, and shows an idempotent retry being deduplicated.
