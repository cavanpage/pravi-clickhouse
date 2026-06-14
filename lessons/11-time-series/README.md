# 11 · Time series

**Goal:** handle time-series data the ClickHouse way — bucketing, downsampling
rollups, gap filling, moving windows, aligning series with `ASOF JOIN`, and the
codecs that make temporal data tiny.

Docs: [Time-series use case](https://clickhouse.com/docs/use-cases/time-series) ·
[WITH FILL](https://clickhouse.com/docs/sql-reference/statements/select/order-by#order-by-expr-with-fill-modifier) ·
[ASOF JOIN](https://clickhouse.com/docs/sql-reference/statements/select/join#asof-join-usage) ·
[TimeSeries engine](https://clickhouse.com/docs/engines/table-engines/integrations/time-series)

ClickHouse is one of the most popular databases for observability and metrics.
This lesson ties together ideas from earlier lessons (codecs from 02,
materialized-view rollups from 03) and adds the time-specific tooling.

## 1. Schema & codecs for metrics

Metrics are `(timestamp, series-key, value)`. Two codec choices do most of the
work:

- **Timestamps** are monotonically increasing → `DateTime CODEC(DoubleDelta,
  ZSTD)`. DoubleDelta stores the *change in the gap* between readings, which is
  near-zero for regular intervals.
- **Float gauges** (temperature, CPU%) → `Float64 CODEC(Gorilla, ZSTD)`. Gorilla
  (from Facebook's TSDB paper) XOR-compresses slowly-changing floats.

Order by `(series-key, timestamp)` so each series' points are contiguous.

## 2. Time bucketing

Roll raw points up to fixed buckets with `toStartOf*` / `toStartOfInterval`:

```sql
SELECT toStartOfInterval(ts, INTERVAL 5 MINUTE) AS bucket, avg(value)
FROM metrics GROUP BY bucket ORDER BY bucket;
```

`toStartOfMinute/Hour/Day` are shortcuts; `toStartOfInterval(ts, INTERVAL n unit)`
is the general form.

## 3. Downsampling with a rollup materialized view

Querying billions of raw points per dashboard is wasteful. Maintain a
**pre-aggregated rollup** with an incremental MV into an `AggregatingMergeTree`
(exactly the pattern from lesson 03), keyed by `(series, bucket)`. Dashboards hit
the small rollup; raw data can age out via TTL (lesson 05).

## 4. Gap filling: `WITH FILL`

Real series have missing intervals (sensor offline). A plain `GROUP BY` simply
omits empty buckets, which breaks charts and rate math. `ORDER BY ... WITH FILL`
synthesises the missing rows:

```sql
SELECT bucket, avg(value) AS v
FROM metrics GROUP BY bucket
ORDER BY bucket WITH FILL STEP INTERVAL 1 HOUR
INTERPOLATE (v AS v);    -- carry last value forward instead of default 0
```

`STEP` sets the cadence; `INTERPOLATE` controls how filled rows get values
(default leaves them at the column default, e.g. 0).

## 5. Moving windows

Window functions give moving averages, running totals, and deltas without a
self-join:

```sql
avg(value) OVER (PARTITION BY sensor_id ORDER BY ts
                 ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)  -- 7-point moving avg
```

## 6. Aligning two series: `ASOF JOIN`

To join readings that don't share exact timestamps (e.g. a price series to a
trade series), `ASOF JOIN` matches each left row to the **most recent** right row
at or before its time:

```sql
SELECT t.ts, t.value, m.value AS latest_metric
FROM trades AS t
ASOF JOIN metrics AS m ON t.sensor_id = m.sensor_id AND t.ts >= m.ts;
```

The last join condition must be an inequality (`>=`/`>`/`<=`/`<`).

## 7. The dedicated `TimeSeries` engine (advanced)

ClickHouse has a `TimeSeries` table engine that models the Prometheus data
(samples + tags + metadata) and lets ClickHouse act as a Prometheus
remote-write/read backend. It's the right tool when you're ingesting Prometheus
metrics specifically; for general metrics, a plain MergeTree with the schema
above is simpler and faster. The `lesson.sql` shows it as an optional appendix.

## What you'll do in `lesson.sql`
Generate a synthetic multi-sensor metrics table with proper codecs, bucket and
downsample it, fill gaps with `WITH FILL`/`INTERPOLATE`, compute a moving
average, and align two series with `ASOF JOIN`.
