-- ============================================================================
-- Lesson 02 · Data types
-- Prereq:  make load-data
-- Run:     make lesson N=02
--
-- Same logical data, two schemas. We compare compressed size on disk.
-- ============================================================================

-- A) The naive schema: everything wide, stringly-typed, nullable.
--    This is what you get if you don't think about types.
CREATE OR REPLACE TABLE trips_naive
(
    pickup_datetime  DateTime,            -- fine
    passenger_count  Int64,               -- way too big for 0-9
    payment_type     String,              -- low-cardinality, should be Enum/LC
    pickup_ntaname   Nullable(String),    -- low-cardinality + needless Nullable
    total_amount     Float64              -- Float32 is plenty for dollars
)
ENGINE = MergeTree
ORDER BY pickup_datetime;

-- B) The optimized schema: smallest correct types + codecs.
CREATE OR REPLACE TABLE trips_typed
(
    -- timestamps are nearly sorted -> DoubleDelta crushes them
    pickup_datetime  DateTime CODEC(DoubleDelta, ZSTD(1)),
    passenger_count  UInt8,
    payment_type     Enum('CSH' = 1, 'CRE' = 2, 'NOC' = 3, 'DIS' = 4, 'UNK' = 5),
    pickup_ntaname   LowCardinality(String),
    total_amount     Float32 CODEC(ZSTD(1))
)
ENGINE = MergeTree
ORDER BY pickup_datetime;

-- Load identical rows into both.
INSERT INTO trips_naive
SELECT pickup_datetime, passenger_count, payment_type, pickup_ntaname, total_amount
FROM trips;

INSERT INTO trips_typed
SELECT pickup_datetime, passenger_count, payment_type, pickup_ntaname, total_amount
FROM trips;

-- ----------------------------------------------------------------------------
-- Compare total compressed size. Same data, very different footprint.
-- ----------------------------------------------------------------------------
SELECT
    table,
    formatReadableSize(sum(data_compressed_bytes))   AS compressed,
    formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 1) AS ratio
FROM system.columns
WHERE database = currentDatabase()
  AND table IN ('trips_naive', 'trips_typed')
GROUP BY table
ORDER BY table;

-- ----------------------------------------------------------------------------
-- Per-column breakdown — see exactly which columns the better types saved.
-- ----------------------------------------------------------------------------
SELECT
    table,
    name AS column,
    type,
    formatReadableSize(data_compressed_bytes) AS compressed
FROM system.columns
WHERE database = currentDatabase()
  AND table IN ('trips_naive', 'trips_typed')
ORDER BY name, table;

-- ----------------------------------------------------------------------------
-- Try it: change ZSTD(1) to ZSTD(3), or add Delta to total_amount, reload,
-- and re-measure. Stronger codecs trade CPU for size.
-- ----------------------------------------------------------------------------
