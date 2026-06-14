-- ============================================================================
-- Lesson 00 · Getting started
-- Run with:  make lesson N=00     (or step through it in `make client`)
-- ============================================================================

-- Where am I? Which version?
SELECT version() AS clickhouse_version, currentDatabase() AS db;

-- ----------------------------------------------------------------------------
-- 1. Create a MergeTree table.
--    ORDER BY is the most important line here — it defines the primary key
--    (the on-disk sort order). More on that in lesson 01.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE hello_events
(
    event_time  DateTime,
    user_id     UInt32,
    event_type  LowCardinality(String),
    value       Float64
)
ENGINE = MergeTree
ORDER BY (event_type, event_time);

-- ----------------------------------------------------------------------------
-- 2. Insert some rows. ClickHouse loves batches — here's one INSERT with many
--    rows (lesson 06 explains why one big insert beats many small ones).
-- ----------------------------------------------------------------------------
INSERT INTO hello_events (event_time, user_id, event_type, value) VALUES
    ('2026-06-01 09:00:00', 1, 'click',    1.0),
    ('2026-06-01 09:01:00', 2, 'view',     0.0),
    ('2026-06-01 09:02:00', 1, 'purchase', 49.99),
    ('2026-06-01 09:03:00', 3, 'click',    1.0),
    ('2026-06-01 09:04:00', 2, 'purchase', 19.95);

-- ----------------------------------------------------------------------------
-- 3. Query it. Aggregations are ClickHouse's bread and butter.
-- ----------------------------------------------------------------------------
SELECT
    event_type,
    count()         AS events,
    round(sum(value), 2) AS total_value
FROM hello_events
GROUP BY event_type
ORDER BY events DESC;

-- ----------------------------------------------------------------------------
-- 4. Inspect the physical layout. Each INSERT created a "part"; merges combine
--    them. (Run a few INSERTs, then watch the part count shrink over time.)
-- ----------------------------------------------------------------------------
SELECT
    name        AS part_name,
    rows,
    formatReadableSize(bytes_on_disk) AS size,
    active
FROM system.parts
WHERE table = 'hello_events' AND database = currentDatabase();

-- ----------------------------------------------------------------------------
-- 5. EXPLAIN: see how the primary key prunes data before reading.
--    With ORDER BY (event_type, event_time), filtering on event_type lets
--    ClickHouse skip granules that can't match.
-- ----------------------------------------------------------------------------
EXPLAIN indexes = 1
SELECT count() FROM hello_events WHERE event_type = 'purchase';

-- ----------------------------------------------------------------------------
-- 6. The scoreboard: how much data did a query actually read?
--    query_log is asynchronous, so flush it first.
-- ----------------------------------------------------------------------------
SELECT count() FROM hello_events WHERE event_type = 'purchase';

SYSTEM FLUSH LOGS;

SELECT
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) AS read_bytes,
    query
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE '%hello_events%purchase%'
  AND current_database = currentDatabase()
ORDER BY event_time DESC
LIMIT 3;

-- Clean up if you like:
-- DROP TABLE hello_events;
