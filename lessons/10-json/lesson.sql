-- ============================================================================
-- Lesson 10 · JSON & semi-structured data
-- Run:  make lesson N=10
-- Requires ClickHouse 24.8+ for the production JSON type (we pin 26.3).
-- ============================================================================

-- A JSON column with hints: type the paths we query, skip the noise.
CREATE OR REPLACE TABLE app_events
(
    id   UInt64,
    ts   DateTime,
    data JSON(
        user.id UInt32,          -- typed hint
        user.tier LowCardinality(String),
        SKIP debug,              -- never store the debug path
        SKIP REGEXP '^tmp_',     -- skip transient paths
        max_dynamic_paths = 256
    )
)
ENGINE = MergeTree
ORDER BY id;

-- Insert nested, semi-structured events. Note each row has slightly different
-- shape — that's the point of JSON.
INSERT INTO app_events VALUES
    (1, now(), '{"user":{"id":123,"tier":"pro"},"action":"login","ip":"10.0.0.1"}'),
    (2, now(), '{"user":{"id":456,"tier":"free"},"action":"purchase","amount":49.99,"items":3}'),
    (3, now(), '{"user":{"id":123,"tier":"pro"},"action":"logout","debug":"ignored","tmp_x":1}');

-- ----------------------------------------------------------------------------
-- 1. Query typed paths directly (dot notation). These return concrete types.
-- ----------------------------------------------------------------------------
SELECT
    data.user.id   AS user_id,     -- UInt32 (hinted)
    data.user.tier AS tier,        -- LowCardinality(String) (hinted)
    count()        AS events
FROM app_events
GROUP BY user_id, tier
ORDER BY events DESC;

-- ----------------------------------------------------------------------------
-- 2. Query dynamic (un-hinted) paths. They come back as Dynamic — cast them.
-- ----------------------------------------------------------------------------
SELECT
    data.action::String        AS action,
    data.amount::Nullable(Float64) AS amount   -- absent in some rows -> NULL
FROM app_events
ORDER BY id;

-- ----------------------------------------------------------------------------
-- 3. Inspect what paths/types ClickHouse actually stored. SKIP'd paths and the
--    'debug'/'tmp_x' fields should be absent.
-- ----------------------------------------------------------------------------
SELECT
    arrayJoin(JSONAllPathsWithTypes(data)) AS path_and_type
FROM app_events;

SELECT DISTINCT arrayJoin(JSONAllPaths(data)) AS stored_path
FROM app_events
ORDER BY stored_path;

-- ----------------------------------------------------------------------------
-- 4. JSON vs String: when you never look inside, String is simpler/smaller.
--    Store the same payloads as raw String for comparison.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE app_events_str
(
    id   UInt64,
    ts   DateTime,
    data String
)
ENGINE = MergeTree ORDER BY id;

INSERT INTO app_events_str VALUES
    (1, now(), '{"user":{"id":123,"tier":"pro"},"action":"login","ip":"10.0.0.1"}'),
    (2, now(), '{"user":{"id":456,"tier":"free"},"action":"purchase","amount":49.99,"items":3}'),
    (3, now(), '{"user":{"id":123,"tier":"pro"},"action":"logout"}');

-- You CAN extract from a String with JSON functions, but every query re-parses
-- the whole text — no columnar subcolumns, no path pruning:
SELECT JSONExtractString(data, 'action') AS action FROM app_events_str ORDER BY id;

-- Rule of thumb: query inside it -> JSON type. Store-and-return whole -> String.
