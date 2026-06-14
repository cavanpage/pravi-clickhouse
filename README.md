# Pravi Clickhouse

A hands-on course for learning [ClickHouse](https://clickhouse.com/docs) by
doing. Each lesson implements one of ClickHouse's
[official best practices](https://clickhouse.com/docs/best-practices) against a
real dataset (NYC taxi trips), with both **SQL** and **Python** examples, and
explains *why* — not just *how*.

Everything runs locally in Docker. No cloud account needed.

---

## Quick start

You need [Docker](https://docs.docker.com/get-docker/) (with Compose v2) and,
for the Python examples, Python 3.9+.

```bash
# 1. Start ClickHouse (pulls the image the first time, ~1-2 min)
make up

# 2. Load the sample dataset (~3M NYC taxi trips, pulled from S3)
make load-data

# 3. Open a SQL shell and poke around
make client
```

Then work through the lessons in order:

```bash
make lesson N=00        # run a lesson's lesson.sql top to bottom
# or open lessons/00-getting-started/lesson.sql and run statements yourself
```

Prefer a GUI? The HTTP **Play UI** is at <http://localhost:8123/play>
(user `learner`, password `learn`).

For Python:

```bash
cd python
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python ch.py                                  # smoke test
python ../lessons/06-insert-strategy/example.py
```

---

## The curriculum

The lessons map directly onto ClickHouse's ten documented best practices, with a
getting-started primer first and a time-series deep-dive at the end.

| # | Lesson | What you'll learn |
|---|--------|-------------------|
| 00 | [Getting started](lessons/00-getting-started/) | MergeTree, inserting & querying, `system` tables, `EXPLAIN` |
| 01 | [Primary keys & ORDER BY](lessons/01-primary-keys/) | The sparse index, cardinality ordering, granule pruning |
| 02 | [Data types](lessons/02-data-types/) | `LowCardinality`, `Enum`, avoiding `Nullable`, codecs, compression |
| 03 | [Materialized views](lessons/03-materialized-views/) | Incremental vs refreshable MVs, `AggregatingMergeTree`, `-State`/`-Merge` |
| 04 | [JOINs](lessons/04-joins/) | Join order, join algorithms, dictionaries for lookups |
| 05 | [Partitioning](lessons/05-partitioning/) | `PARTITION BY`, partition pruning, fast drops, TTL |
| 06 | [Insert strategy](lessons/06-insert-strategy/) | Batching, async inserts, idempotent retries, native vs HTTP |
| 07 | [Data skipping indices](lessons/07-skipping-indices/) | `minmax`, `set`, `bloom_filter`, when they actually help |
| 08 | [Avoid mutations](lessons/08-avoid-mutations/) | Lightweight deletes, `ReplacingMergeTree`, soft deletes |
| 09 | [Avoid OPTIMIZE FINAL](lessons/09-avoid-optimize-final/) | How merges work, the `FINAL` modifier, what to do instead |
| 10 | [JSON & semi-structured data](lessons/10-json/) | The native `JSON` type, typed hints, paths, vs `String` |
| 11 | [Time series](lessons/11-time-series/) | Bucketing, downsampling rollups, gap filling, windows, `ASOF JOIN`, codecs |

Each lesson folder contains:

- **`README.md`** — the concepts, the *why*, and links to the relevant docs
- **`lesson.sql`** — runnable SQL you can step through
- **`example.py`** — the same ideas from an app, via `clickhouse-connect`

---

## How to use this repo

These lessons are meant to be *run and modified*, not just read. The fastest way
to learn ClickHouse is to watch the numbers change:

- Almost every lesson ends with a query against `system.query_log` or uses
  `EXPLAIN` to show **how many rows ClickHouse actually read**. That number is
  the scoreboard — a good primary key or partition key makes it drop by orders
  of magnitude.
- Break things on purpose. Drop the `ORDER BY`, add a `Nullable`, insert one row
  at a time — then measure the cost.

## Useful commands

```bash
make help        # list everything
make up          # start ClickHouse and wait until ready
make down        # stop (keeps your data)
make client      # interactive SQL shell
make q Q="SELECT version()"          # run an inline query
make sql F=path/to/file.sql          # run a .sql file
make lesson N=03                     # run a lesson's lesson.sql
make clean       # reset the `learn` database
make nuke        # delete everything including the data volume
```

## What's under the hood

- **`docker-compose.yml`** — single ClickHouse node, pinned to the **26.3 LTS**
  line, with ports `8123` (HTTP) and `9000` (native) exposed.
- **`config/`** — light server/user config (readable logs, query logging on so
  the lessons can show you read-row counts).
- **`data-loaders/`** — SQL that pulls sample datasets straight from object
  storage via the `s3()` table function.
- **`python/ch.py`** — one place for connection settings, shared by every
  Python example.

> ClickHouse moves fast. These lessons target the 26.x line and link to the live
> docs throughout — when in doubt, the [docs](https://clickhouse.com/docs) win.
