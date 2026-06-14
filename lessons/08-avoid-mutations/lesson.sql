-- ============================================================================
-- Lesson 08 · Avoid mutations
-- Run:  make lesson N=08
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ReplacingMergeTree: "update" by inserting a new version. The engine keeps
--    the row with the highest version per sorting key.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE users
(
    id          UInt64,
    name        String,
    plan        LowCardinality(String),
    is_deleted  UInt8 DEFAULT 0,
    updated_at  DateTime
)
ENGINE = ReplacingMergeTree(updated_at, is_deleted)   -- version, then deleted flag
ORDER BY id;

-- Initial inserts.
INSERT INTO users (id, name, plan, updated_at) VALUES
    (1, 'Ada',   'free', '2026-01-01 00:00:00'),
    (2, 'Babb',  'free', '2026-01-01 00:00:00'),
    (3, 'Chen',  'pro',  '2026-01-01 00:00:00');

-- "Update" user 1 to pro: just insert a newer-versioned row. No mutation.
INSERT INTO users (id, name, plan, updated_at) VALUES
    (1, 'Ada', 'pro', '2026-06-01 00:00:00');

-- Without FINAL you still see BOTH versions (merges haven't run yet):
SELECT id, name, plan, updated_at FROM users ORDER BY id, updated_at;

-- FINAL collapses to the latest version per id at query time:
SELECT id, name, plan, updated_at FROM users FINAL ORDER BY id;
-- user 1 is now 'pro'. (FINAL has a cost — see lesson 09.)

-- ----------------------------------------------------------------------------
-- 2. Soft delete: insert a tombstone with is_deleted = 1 and a newer version.
--    ReplacingMergeTree(version, is_deleted) can drop these on merge.
-- ----------------------------------------------------------------------------
INSERT INTO users (id, name, plan, is_deleted, updated_at) VALUES
    (2, 'Babb', 'free', 1, '2026-06-10 00:00:00');

-- The live view: latest version, excluding deleted rows.
SELECT id, name, plan FROM users FINAL WHERE is_deleted = 0 ORDER BY id;
-- user 2 is gone, no part was rewritten.

-- ----------------------------------------------------------------------------
-- 3. Lightweight DELETE: the cheap way when you genuinely must delete.
--    Marks rows deleted immediately; physical removal happens on merge.
-- ----------------------------------------------------------------------------
DELETE FROM users WHERE id = 3;
SELECT id, name FROM users FINAL ORDER BY id;

-- ----------------------------------------------------------------------------
-- 4. A real mutation, for contrast. ALTER UPDATE rewrites affected parts in
--    the background. Watch it in system.mutations.
-- ----------------------------------------------------------------------------
ALTER TABLE users UPDATE plan = 'enterprise' WHERE id = 1;

SELECT
    command,
    is_done,
    parts_to_do,
    create_time
FROM system.mutations
WHERE database = currentDatabase() AND table = 'users'
ORDER BY create_time DESC
LIMIT 5;
-- Note it's asynchronous (is_done flips to 1 once the part rewrite finishes).
-- This is fine for a one-off fix, terrible as a per-row workload.
