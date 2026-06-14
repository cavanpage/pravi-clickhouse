-- ============================================================================
-- Lesson 11 · Time series
-- Run:  make lesson N=11   (self-contained — generates its own data)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. A metrics table with time-series codecs (lesson 02 applied to temporal
--    data). DoubleDelta crushes regular timestamps; Gorilla crushes gauges.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS metrics;
CREATE TABLE metrics
(
    ts        DateTime   CODEC(DoubleDelta, ZSTD(1)),
    sensor_id LowCardinality(String),
    value     Float64    CODEC(Gorilla, ZSTD(1))
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(ts)
ORDER BY (sensor_id, ts)
-- Force "wide" parts (one file per column) so system.columns can report
-- per-column compressed sizes for the codec comparison below. On big tables
-- this happens automatically; our synthetic table is small enough to stay
-- "compact" (all columns in one file) otherwise.
SETTINGS min_bytes_for_wide_part = 0;

-- One reading per minute for two days, three sensors.
-- sensor_a has a deliberate ~2 hour gap (numbers 600..720) to demo gap filling.
INSERT INTO metrics
SELECT
    toDateTime('2026-06-01 00:00:00') + toIntervalMinute(number) AS ts,
    'sensor_a' AS sensor_id,
    20 + 5 * sin(number / 120.0) + (rand() % 100) / 100.0 AS value
FROM numbers(2880)
WHERE number < 600 OR number > 720;        -- punch a gap

INSERT INTO metrics
SELECT
    toDateTime('2026-06-01 00:00:00') + toIntervalMinute(number),
    'sensor_b',
    50 + 10 * cos(number / 90.0) + (rand() % 100) / 100.0
FROM numbers(2880);

INSERT INTO metrics
SELECT
    toDateTime('2026-06-01 00:00:00') + toIntervalMinute(number),
    'sensor_c',
    100 + (number / 100.0) + (rand() % 50) / 100.0   -- slow upward drift
FROM numbers(2880);

-- See how well the codecs compressed the temporal data:
SELECT
    name AS column, type,
    formatReadableSize(data_compressed_bytes)   AS compressed,
    formatReadableSize(data_uncompressed_bytes) AS uncompressed
FROM system.columns
WHERE database = currentDatabase() AND table = 'metrics'
ORDER BY name;

-- ----------------------------------------------------------------------------
-- 2. Time bucketing: average per 1-hour bucket per sensor.
-- ----------------------------------------------------------------------------
SELECT
    sensor_id,
    toStartOfInterval(ts, INTERVAL 1 HOUR) AS hour,
    round(avg(value), 2) AS avg_value,
    count() AS points
FROM metrics
GROUP BY sensor_id, hour
ORDER BY sensor_id, hour
LIMIT 10;

-- ----------------------------------------------------------------------------
-- 3. Downsampling rollup via an incremental MV (lesson 03 pattern, for time).
--    Dashboards then read tiny pre-aggregated buckets, not raw points.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS metrics_1h;
CREATE TABLE metrics_1h
(
    hour        DateTime,
    sensor_id   LowCardinality(String),
    avg_state   AggregateFunction(avg, Float64),
    max_state   AggregateFunction(max, Float64),
    count_state AggregateFunction(count)
)
ENGINE = AggregatingMergeTree
ORDER BY (sensor_id, hour);

DROP TABLE IF EXISTS metrics_1h_mv;
CREATE MATERIALIZED VIEW metrics_1h_mv TO metrics_1h AS
SELECT
    toStartOfInterval(ts, INTERVAL 1 HOUR) AS hour,
    sensor_id,
    avgState(value)   AS avg_state,
    maxState(value)   AS max_state,
    countState()      AS count_state
FROM metrics
GROUP BY hour, sensor_id;

-- Backfill existing data (MV only triggers on future inserts).
INSERT INTO metrics_1h
SELECT toStartOfInterval(ts, INTERVAL 1 HOUR), sensor_id,
       avgState(value), maxState(value), countState()
FROM metrics GROUP BY 1, 2;

SELECT
    sensor_id, hour,
    round(avgMerge(avg_state), 2) AS avg_value,
    round(maxMerge(max_state), 2) AS max_value
FROM metrics_1h
GROUP BY sensor_id, hour
ORDER BY sensor_id, hour
LIMIT 5;

-- ----------------------------------------------------------------------------
-- 4. Gap filling with WITH FILL. sensor_a is missing ~2 hours; a plain GROUP BY
--    just omits those buckets. WITH FILL synthesises them on a fixed cadence;
--    INTERPOLATE carries the last value forward instead of leaving 0.
-- ----------------------------------------------------------------------------
-- Without fill — note the missing hours around the gap:
SELECT toStartOfInterval(ts, INTERVAL 1 HOUR) AS hour, round(avg(value), 2) AS v
FROM metrics
WHERE sensor_id = 'sensor_a'
GROUP BY hour
ORDER BY hour
LIMIT 24;

-- With fill — every hour present, gaps interpolated from the previous value:
SELECT toStartOfInterval(ts, INTERVAL 1 HOUR) AS hour, round(avg(value), 2) AS v
FROM metrics
WHERE sensor_id = 'sensor_a'
GROUP BY hour
ORDER BY hour WITH FILL STEP INTERVAL 1 HOUR
INTERPOLATE (v AS v)
LIMIT 24;

-- ----------------------------------------------------------------------------
-- 5. Moving average with a window function (7-point trailing mean).
-- ----------------------------------------------------------------------------
SELECT
    ts,
    round(value, 2) AS value,
    round(avg(value) OVER (
        PARTITION BY sensor_id ORDER BY ts
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_7
FROM metrics
WHERE sensor_id = 'sensor_b'
ORDER BY ts
LIMIT 10;

-- ----------------------------------------------------------------------------
-- 6. ASOF JOIN: align each metric reading to the most recent SETPOINT change.
--    The last ON condition is an inequality (ts >= setpoint.ts).
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS setpoints;
CREATE TABLE setpoints (sensor_id LowCardinality(String), ts DateTime, target Float64)
ENGINE = MergeTree ORDER BY (sensor_id, ts);

INSERT INTO setpoints VALUES
    ('sensor_a', '2026-06-01 00:00:00', 22.0),
    ('sensor_a', '2026-06-01 12:00:00', 24.0),
    ('sensor_a', '2026-06-02 00:00:00', 21.0);

SELECT
    m.ts,
    round(m.value, 2)            AS reading,
    s.target,
    round(m.value - s.target, 2) AS deviation
FROM metrics AS m
ASOF JOIN setpoints AS s
    ON m.sensor_id = s.sensor_id AND m.ts >= s.ts
WHERE m.sensor_id = 'sensor_a'
ORDER BY m.ts
LIMIT 5;

-- ----------------------------------------------------------------------------
-- 7. (Optional appendix) The dedicated TimeSeries engine for Prometheus-style
--    data. Uncomment to explore; it creates several inner tables for samples,
--    tags, and metadata. For general metrics the MergeTree above is simpler.
-- ----------------------------------------------------------------------------
-- SET allow_experimental_time_series_table = 1;
-- CREATE TABLE prom_metrics ENGINE = TimeSeries;
-- SHOW TABLES LIKE '%prom_metrics%';
