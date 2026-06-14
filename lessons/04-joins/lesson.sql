-- ============================================================================
-- Lesson 04 · JOINs
-- Prereq:  make load-data
-- Run:     make lesson N=04
-- ============================================================================

-- A small dimension table: neighbourhood -> borough + a flag.
-- (Synthesised from the trips data so the lesson is self-contained.)
CREATE OR REPLACE TABLE neighbourhoods
(
    name     LowCardinality(String),
    borough  LowCardinality(String),
    is_airport UInt8
)
ENGINE = MergeTree
ORDER BY name;

INSERT INTO neighbourhoods
SELECT
    pickup_ntaname AS name,
    -- toy borough assignment just for the exercise
    transform(cityHash64(pickup_ntaname) % 5,
              [0, 1, 2, 3, 4],
              ['Manhattan', 'Brooklyn', 'Queens', 'Bronx', 'Staten Island'],
              'Unknown') AS borough,
    pickup_ntaname ILIKE '%airport%' AS is_airport
FROM trips
GROUP BY pickup_ntaname;

-- ----------------------------------------------------------------------------
-- 1. Correct join: large `trips` on the left, small `neighbourhoods` on the
--    right (built into the in-memory hash table).
-- ----------------------------------------------------------------------------
SELECT
    n.borough,
    count()                       AS trips,
    round(avg(t.total_amount), 2) AS avg_fare
FROM trips AS t
INNER JOIN neighbourhoods AS n ON t.pickup_ntaname = n.name
GROUP BY n.borough
ORDER BY trips DESC;

-- ----------------------------------------------------------------------------
-- 2. See the chosen algorithm and read volumes via EXPLAIN.
-- ----------------------------------------------------------------------------
EXPLAIN actions = 1
SELECT n.borough, count()
FROM trips AS t
INNER JOIN neighbourhoods AS n ON t.pickup_ntaname = n.name
GROUP BY n.borough;

-- Force a different algorithm to compare (works regardless of table sizes here):
SELECT n.borough, count() AS trips
FROM trips AS t
INNER JOIN neighbourhoods AS n ON t.pickup_ntaname = n.name
GROUP BY n.borough
SETTINGS join_algorithm = 'full_sorting_merge';

-- ----------------------------------------------------------------------------
-- 3. The dictionary approach: no JOIN at all.
--    Define a dictionary sourced from the neighbourhoods table, then dictGet().
-- ----------------------------------------------------------------------------
CREATE OR REPLACE DICTIONARY nta_dict
(
    name     String,
    borough  String,
    is_airport UInt8
)
PRIMARY KEY name
-- A CLICKHOUSE dictionary source connects back to the server as a client, so it
-- needs credentials. We use the learner user this repo creates.
SOURCE(CLICKHOUSE(TABLE 'neighbourhoods' DB 'learn' USER 'learner' PASSWORD 'learn'))
LIFETIME(MIN 600 MAX 900)        -- refresh window in seconds
LAYOUT(COMPLEX_KEY_HASHED());

SELECT
    dictGet('nta_dict', 'borough', pickup_ntaname) AS borough,
    count()                       AS trips,
    round(avg(total_amount), 2)   AS avg_fare
FROM trips
GROUP BY borough
ORDER BY trips DESC;
-- Same answer as the join, but a pure in-memory lookup — no hash build per query.

-- ----------------------------------------------------------------------------
-- Compare read/timing of the join vs the dictionary version in query_log.
-- ----------------------------------------------------------------------------
SYSTEM FLUSH LOGS;
SELECT
    substr(query, 1, 60) AS query_start,
    read_rows,
    query_duration_ms,
    memory_usage
FROM system.query_log
WHERE type = 'QueryFinish'
  AND current_database = currentDatabase()
  AND (query LIKE '%borough%')
  AND query NOT LIKE '%query_log%'
ORDER BY event_time DESC
LIMIT 4;
