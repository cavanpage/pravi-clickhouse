-- ============================================================================
-- Lesson 07 · Data skipping indices
-- Prereq:  make load-data
-- Run:     make lesson N=07
-- ============================================================================

-- A trips copy ordered by time. trip_distance and passenger_count are NOT in
-- the key, so filters on them normally scan everything.
CREATE OR REPLACE TABLE trips_skip
(
    pickup_datetime  DateTime,
    passenger_count  UInt8,
    trip_distance    Float32,
    total_amount     Float32,
    -- minmax suits trip_distance: long trips cluster in time (airport runs etc.)
    INDEX idx_distance trip_distance TYPE minmax GRANULARITY 4,
    -- set() suits the handful of distinct passenger counts
    INDEX idx_pax passenger_count TYPE set(16) GRANULARITY 4
)
ENGINE = MergeTree
ORDER BY pickup_datetime;

INSERT INTO trips_skip
SELECT pickup_datetime, passenger_count, trip_distance, total_amount FROM trips;

-- Make sure indices are built for existing data.
ALTER TABLE trips_skip MATERIALIZE INDEX idx_distance;
ALTER TABLE trips_skip MATERIALIZE INDEX idx_pax;

-- ----------------------------------------------------------------------------
-- 1. EXPLAIN shows the skip index being used and how many granules it drops.
-- ----------------------------------------------------------------------------
EXPLAIN indexes = 1
SELECT count() FROM trips_skip WHERE trip_distance > 50;

-- ----------------------------------------------------------------------------
-- 2. Measure: same query WITH the index vs. with skip indices disabled.
--    use_skip_indexes = 0 turns them off so you can see the difference.
-- ----------------------------------------------------------------------------
SELECT count() FROM trips_skip WHERE trip_distance > 50;                         -- index on
SELECT count() FROM trips_skip WHERE trip_distance > 50
    SETTINGS use_skip_indexes = 0;                                              -- index off

SYSTEM FLUSH LOGS;
SELECT
    if(Settings['use_skip_indexes'] = '0', 'index OFF', 'index ON') AS mode,
    read_rows,
    query_duration_ms
FROM system.query_log
WHERE type = 'QueryFinish'
  AND current_database = currentDatabase()
  AND query LIKE '%trips_skip WHERE trip_distance > 50%'
  AND query NOT LIKE '%query_log%'
ORDER BY event_time DESC
LIMIT 2;
-- If read_rows is much lower with the index ON, it's earning its keep.

-- ----------------------------------------------------------------------------
-- 3. set() index on a low-cardinality column.
-- ----------------------------------------------------------------------------
EXPLAIN indexes = 1
SELECT count() FROM trips_skip WHERE passenger_count = 6;

-- ----------------------------------------------------------------------------
-- 4. Counter-example: an index on a SCATTERED value can't skip anything.
--    total_amount varies in every block, so a minmax index on it won't help a
--    range filter. Try adding one and measuring — read_rows won't budge.
-- ----------------------------------------------------------------------------
