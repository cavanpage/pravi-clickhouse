-- ============================================================================
-- Lesson 01 · Primary keys & ORDER BY
-- Prereq:  make load-data   (needs the `trips` table)
-- Run:     make lesson N=01
--
-- We build two tables with the SAME data but DIFFERENT ORDER BY, then run the
-- same query against each and compare how many rows ClickHouse had to read.
-- ============================================================================

-- A) Key chosen for the queries we run: filter on pickup_ntaname, then time.
--    Low-cardinality column (a few hundred neighbourhoods) leads.
CREATE OR REPLACE TABLE trips_by_nta
(
    pickup_datetime  DateTime,
    pickup_ntaname   LowCardinality(String),
    passenger_count  UInt8,
    total_amount     Float32
)
ENGINE = MergeTree
ORDER BY (pickup_ntaname, pickup_datetime);

-- B) Key that ignores how we query: ordered only by time.
CREATE OR REPLACE TABLE trips_by_time
(
    pickup_datetime  DateTime,
    pickup_ntaname   LowCardinality(String),
    passenger_count  UInt8,
    total_amount     Float32
)
ENGINE = MergeTree
ORDER BY (pickup_datetime);

-- Same data into both.
INSERT INTO trips_by_nta
SELECT pickup_datetime, pickup_ntaname, passenger_count, total_amount FROM trips;

INSERT INTO trips_by_time
SELECT pickup_datetime, pickup_ntaname, passenger_count, total_amount FROM trips;

-- ----------------------------------------------------------------------------
-- The sparse index in action. EXPLAIN shows granules selected vs. total.
-- On trips_by_nta, filtering by neighbourhood prunes almost everything.
-- ----------------------------------------------------------------------------
EXPLAIN indexes = 1
SELECT count(), round(avg(total_amount), 2)
FROM trips_by_nta
WHERE pickup_ntaname = 'Midtown-Midtown South';

-- The same query on the time-ordered table can't use the index for this filter:
-- it has to scan the whole table.
EXPLAIN indexes = 1
SELECT count(), round(avg(total_amount), 2)
FROM trips_by_time
WHERE pickup_ntaname = 'Midtown-Midtown South';

-- ----------------------------------------------------------------------------
-- Now actually run both and let query_log tell us read_rows for each.
-- ----------------------------------------------------------------------------
SELECT count(), round(avg(total_amount), 2)
FROM trips_by_nta
WHERE pickup_ntaname = 'Midtown-Midtown South';

SELECT count(), round(avg(total_amount), 2)
FROM trips_by_time
WHERE pickup_ntaname = 'Midtown-Midtown South';

SYSTEM FLUSH LOGS;

SELECT
    tables[1]                       AS table,
    read_rows,
    formatReadableSize(read_bytes)  AS read_bytes,
    query_duration_ms
FROM system.query_log
WHERE type = 'QueryFinish'
  AND current_database = currentDatabase()
  AND query LIKE '%Midtown-Midtown South%'
  AND query NOT LIKE '%query_log%'
ORDER BY event_time DESC
LIMIT 2;
-- Expect trips_by_nta to read a tiny fraction of what trips_by_time reads.

-- ----------------------------------------------------------------------------
-- Lesson takeaways to try yourself:
--   * Add a query filtering by time range. Now trips_by_time wins. A key only
--     helps queries that filter on its LEADING columns.
--   * Inspect the sparse index size: it's one mark per granule, not per row.
-- ----------------------------------------------------------------------------
SELECT
    table,
    sum(rows)                        AS rows,
    sum(marks)                       AS marks,        -- ~ rows / 8192
    formatReadableSize(sum(primary_key_bytes_in_memory)) AS pk_in_memory
FROM system.parts
WHERE database = currentDatabase()
  AND table IN ('trips_by_nta', 'trips_by_time')
  AND active
GROUP BY table;
