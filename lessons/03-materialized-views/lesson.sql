-- ============================================================================
-- Lesson 03 · Materialized views
-- Prereq:  make load-data
-- Run:     make lesson N=03
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PART 1 — Incremental MV with AggregatingMergeTree
-- Goal: keep per-neighbourhood, per-day stats up to date as trips arrive.
-- ----------------------------------------------------------------------------

-- 1a. Target table. Note the AggregateFunction columns — they hold partial
--     STATES, not finished numbers. ORDER BY is the grouping key.
CREATE OR REPLACE TABLE trips_daily_stats
(
    day             Date,
    pickup_ntaname  LowCardinality(String),
    trips_state     AggregateFunction(count),
    avg_fare_state  AggregateFunction(avg, Float32),
    riders_state    AggregateFunction(sum, UInt8)
)
ENGINE = AggregatingMergeTree
ORDER BY (pickup_ntaname, day);

-- 1b. The materialized view: a trigger that writes -State values to the target
--     for every new block inserted into `trips`.
CREATE MATERIALIZED VIEW IF NOT EXISTS trips_daily_mv
TO trips_daily_stats
AS
SELECT
    toDate(pickup_datetime) AS day,
    pickup_ntaname,
    countState()            AS trips_state,
    avgState(total_amount)  AS avg_fare_state,
    sumState(passenger_count) AS riders_state
FROM trips
GROUP BY day, pickup_ntaname;

-- 1c. The MV only sees FUTURE inserts. Backfill existing data once, by hand,
--     using the same SELECT.
INSERT INTO trips_daily_stats
SELECT
    toDate(pickup_datetime) AS day,
    pickup_ntaname,
    countState(),
    avgState(total_amount),
    sumState(passenger_count)
FROM trips
GROUP BY day, pickup_ntaname;

-- 1d. Read it: finalize states with -Merge. This scans a tiny pre-aggregated
--     table instead of millions of trips.
SELECT
    pickup_ntaname,
    countMerge(trips_state)        AS trips,
    round(avgMerge(avg_fare_state), 2) AS avg_fare,
    sumMerge(riders_state)         AS total_riders
FROM trips_daily_stats
GROUP BY pickup_ntaname
ORDER BY trips DESC
LIMIT 10;

-- 1e. Watch it update live: insert a synthetic trip and re-query that day.
INSERT INTO trips (pickup_datetime, dropoff_datetime, passenger_count,
                   trip_distance, total_amount, payment_type, pickup_ntaname,
                   dropoff_ntaname, trip_id)
VALUES (now(), now(), 3, 2.5, 25.0, 'CRE', 'Test-Neighbourhood',
        'Test-Neighbourhood', 999999999);

SELECT pickup_ntaname, countMerge(trips_state) AS trips
FROM trips_daily_stats
WHERE pickup_ntaname = 'Test-Neighbourhood'
GROUP BY pickup_ntaname;   -- the MV captured the new row automatically

-- ----------------------------------------------------------------------------
-- PART 2 — Refreshable MV (periodic snapshot of a bounded result)
-- Good for a small "leaderboard" that can be a little stale.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE top_neighbourhoods
(
    pickup_ntaname  LowCardinality(String),
    trips           UInt64,
    avg_fare        Float64
)
ENGINE = MergeTree
ORDER BY trips;

CREATE MATERIALIZED VIEW IF NOT EXISTS top_neighbourhoods_mv
REFRESH EVERY 1 HOUR
TO top_neighbourhoods
AS
SELECT
    pickup_ntaname,
    count()                   AS trips,
    round(avg(total_amount), 2) AS avg_fare
FROM trips
GROUP BY pickup_ntaname
ORDER BY trips DESC
LIMIT 20;

-- Force an immediate refresh instead of waiting an hour:
SYSTEM REFRESH VIEW top_neighbourhoods_mv;
-- Give it a moment, then:
SELECT * FROM top_neighbourhoods ORDER BY trips DESC LIMIT 10;

-- Inspect refresh status:
SELECT view, status, last_refresh_time, next_refresh_time
FROM system.view_refreshes
WHERE database = currentDatabase();
