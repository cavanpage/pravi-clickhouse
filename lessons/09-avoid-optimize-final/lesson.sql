-- ============================================================================
-- Lesson 09 · Avoid OPTIMIZE FINAL
-- Run:  make lesson N=09
-- ============================================================================

-- A ReplacingMergeTree that will accumulate duplicate versions per id.
CREATE OR REPLACE TABLE prices
(
    sku        UInt32,
    price      Float64,
    version    DateTime
)
ENGINE = ReplacingMergeTree(version)
ORDER BY sku;

-- Insert 5 versions for each of 10,000 SKUs across separate inserts, so there
-- are many parts with duplicates to resolve.
INSERT INTO prices SELECT number, 10 + number % 90, '2026-01-01 00:00:00' FROM numbers(10000);
INSERT INTO prices SELECT number, 11 + number % 90, '2026-02-01 00:00:00' FROM numbers(10000);
INSERT INTO prices SELECT number, 12 + number % 90, '2026-03-01 00:00:00' FROM numbers(10000);
INSERT INTO prices SELECT number, 13 + number % 90, '2026-04-01 00:00:00' FROM numbers(10000);
INSERT INTO prices SELECT number, 14 + number % 90, '2026-05-01 00:00:00' FROM numbers(10000);

-- Raw row count includes all the duplicates:
SELECT count() AS raw_rows, uniq(sku) AS distinct_skus FROM prices;

-- ----------------------------------------------------------------------------
-- Three ways to get the CURRENT price per SKU, cheapest mindset first.
-- ----------------------------------------------------------------------------

-- A) Read-time aggregation: no FINAL, no rewrite. Often the best option.
SELECT sku, argMax(price, version) AS current_price
FROM prices
GROUP BY sku
ORDER BY sku
LIMIT 5;

-- B) SELECT ... FINAL: resolve duplicates on the fly, for THIS query only.
SELECT sku, price AS current_price
FROM prices FINAL
ORDER BY sku
LIMIT 5;

-- C) OPTIMIZE FINAL: force-merge the WHOLE table now. Works, but rewrites
--    everything — and the next insert re-creates parts. Avoid on a schedule.
OPTIMIZE TABLE prices FINAL;
SELECT sku, price FROM prices ORDER BY sku LIMIT 5;   -- now deduped on disk

-- ----------------------------------------------------------------------------
-- Compare the cost. Note how much each approach read / how long it took.
-- ----------------------------------------------------------------------------
SYSTEM FLUSH LOGS;
SELECT
    multiIf(
        query LIKE '%argMax%', 'A: argMax aggregation',
        query LIKE '%FROM prices FINAL%', 'B: SELECT FINAL',
        query LIKE '%OPTIMIZE TABLE prices FINAL%', 'C: OPTIMIZE FINAL',
        'other') AS approach,
    read_rows,
    formatReadableSize(read_bytes) AS read_bytes,
    query_duration_ms
FROM system.query_log
WHERE type = 'QueryFinish'
  AND current_database = currentDatabase()
  AND (query LIKE '%argMax%' OR query LIKE '%prices FINAL%'
       OR query LIKE '%OPTIMIZE TABLE prices%')
  AND query NOT LIKE '%query_log%'
ORDER BY event_time DESC
LIMIT 5;

-- Takeaway: prefer (A) or (B). Reserve OPTIMIZE FINAL for rare, manual cleanups.
