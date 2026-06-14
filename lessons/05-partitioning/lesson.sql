-- ============================================================================
-- Lesson 05 · Partitioning
-- Prereq:  make load-data
-- Run:     make lesson N=05
-- ============================================================================

-- Monthly-partitioned trips table. PARTITION BY is independent of ORDER BY.
CREATE OR REPLACE TABLE trips_monthly
(
    pickup_datetime  DateTime,
    pickup_ntaname   LowCardinality(String),
    passenger_count  UInt8,
    total_amount     Float32
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(pickup_datetime)   -- one partition per month (coarse!)
ORDER BY (pickup_ntaname, pickup_datetime);

INSERT INTO trips_monthly
SELECT pickup_datetime, pickup_ntaname, passenger_count, total_amount FROM trips;

-- ----------------------------------------------------------------------------
-- 1. See the partitions. Each is a separate group of parts on disk.
-- ----------------------------------------------------------------------------
SELECT
    partition,
    sum(rows)                          AS rows,
    count()                            AS parts,
    formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts
WHERE database = currentDatabase() AND table = 'trips_monthly' AND active
GROUP BY partition
ORDER BY partition;

-- ----------------------------------------------------------------------------
-- 2. Partition pruning: a query filtered to one month touches only that
--    partition. Look for "Selected ... parts by partition key" in the output.
-- ----------------------------------------------------------------------------
EXPLAIN indexes = 1
SELECT count()
FROM trips_monthly
WHERE pickup_datetime >= '2015-07-01' AND pickup_datetime < '2015-08-01';

-- ----------------------------------------------------------------------------
-- 3. Cheap data management: drop a whole month instantly (no mutation, just
--    unlinks files). Pick a partition that exists from the list in step 1.
-- ----------------------------------------------------------------------------
-- Example (uncomment and set a real YYYYMM from step 1):
-- ALTER TABLE trips_monthly DROP PARTITION '201507';
-- SELECT count() FROM trips_monthly;   -- those rows are gone, near-instantly

-- ----------------------------------------------------------------------------
-- 4. The anti-pattern: DON'T partition by day. This would create one partition
--    per day -> thousands of tiny partitions, many small parts, slow merges,
--    and eventually "too many parts" errors on insert. Shown here as a warning,
--    not a recommendation:
-- ----------------------------------------------------------------------------
-- CREATE TABLE trips_daily_BAD ( ... )
-- ENGINE = MergeTree
-- PARTITION BY toDate(pickup_datetime)   -- <-- too fine-grained!
-- ORDER BY (pickup_ntaname, pickup_datetime);

-- Inspect how many partitions a daily key WOULD create from this data:
SELECT uniq(toYYYYMM(pickup_datetime)) AS monthly_partitions,
       uniq(toDate(pickup_datetime))   AS daily_partitions_if_we_were_silly
FROM trips;

-- ----------------------------------------------------------------------------
-- 5. TTL: auto-expire old data. Here we keep trips for 5 years past pickup.
--    (Adjust/remove for the sample data, which is historical.)
-- ----------------------------------------------------------------------------
ALTER TABLE trips_monthly
    MODIFY TTL pickup_datetime + INTERVAL 5 YEAR;

-- Verify the TTL is registered:
SELECT name, engine_full
FROM system.tables
WHERE database = currentDatabase() AND name = 'trips_monthly'
FORMAT Vertical;
