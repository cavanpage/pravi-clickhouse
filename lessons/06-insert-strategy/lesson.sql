-- ============================================================================
-- Lesson 06 · Insert strategy
-- Run:  make lesson N=06
-- (The Python example.py is the more illustrative demo for this lesson.)
-- ============================================================================

CREATE OR REPLACE TABLE events
(
    event_time  DateTime,
    user_id     UInt32,
    event_type  LowCardinality(String),
    value       Float64
)
ENGINE = MergeTree
ORDER BY (event_type, event_time)
-- On a plain (non-Replicated) MergeTree, insert dedup is OFF by default.
-- Turn it on so the idempotent-retry demo in step 3 works. (On Replicated
-- tables it's enabled by default via replicated_deduplication_window.)
SETTINGS non_replicated_deduplication_window = 100;

-- ----------------------------------------------------------------------------
-- 1. GOOD: one INSERT with many rows -> one part. Here we synthesise 100k rows
--    in a single statement using numbers().
-- ----------------------------------------------------------------------------
INSERT INTO events
SELECT
    now() - toIntervalSecond(number % 86400) AS event_time,
    (number % 1000)::UInt32                  AS user_id,
    ['click', 'view', 'purchase'][(number % 3) + 1] AS event_type,
    round(randUniform(0, 100), 2)            AS value
FROM numbers(100000);

-- How many parts did that create? (Just one, plus maybe in-flight merges.)
SELECT count() AS parts, sum(rows) AS rows
FROM system.parts
WHERE database = currentDatabase() AND table = 'events' AND active;

-- ----------------------------------------------------------------------------
-- 2. ASYNC inserts: let the server buffer and batch small inserts for you.
--    With wait_for_async_insert = 1 the statement returns only after flush.
-- ----------------------------------------------------------------------------
INSERT INTO events
SETTINGS async_insert = 1, wait_for_async_insert = 1
VALUES (now(), 1, 'click', 1.0);

-- You can also set it for the whole user/session:
-- ALTER USER learner SETTINGS async_insert = 1;

-- Inspect async insert activity:
SYSTEM FLUSH LOGS;
SELECT status, count() AS inserts, sum(rows) AS rows
FROM system.asynchronous_insert_log
WHERE database = currentDatabase() AND table = 'events'
GROUP BY status;

-- ----------------------------------------------------------------------------
-- 3. Idempotent retry: re-inserting the SAME block is deduplicated.
--    Run this exact INSERT twice; the row count only goes up once.
-- ----------------------------------------------------------------------------
INSERT INTO events VALUES ('2030-01-01 00:00:00', 42, 'purchase', 99.0);
INSERT INTO events VALUES ('2030-01-01 00:00:00', 42, 'purchase', 99.0); -- dup

SELECT count() AS rows_for_2030
FROM events WHERE event_time = '2030-01-01 00:00:00';
-- Expect 1, not 2: identical block was recognised and skipped.
-- (Dedup of plain INSERTs is most relevant on Replicated tables; the Python
--  demo shows the cross-network retry pattern explicitly.)
