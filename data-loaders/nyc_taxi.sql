-- Loads the NYC taxi sample dataset (~3 million rows) into the `trips` table.
-- ClickHouse reads the gzipped TSV files directly from public object storage
-- using the s3() table function — no manual download required.
--
-- Run with:  make load-data
-- This takes ~30-60s depending on your connection. It's the dataset used by
-- most lessons in this repo.

-- Notice the deliberate schema choices (covered in lessons 01 and 02):
--   * Enum for payment_type instead of String
--   * LowCardinality(String) for neighborhood names (few distinct values)
--   * DateTime, not DateTime64 (second precision is enough)
--   * PRIMARY KEY ordered low-cardinality -> high-cardinality
-- CREATE OR REPLACE so re-running `make load-data` reloads cleanly instead of
-- appending another 3M rows on top of the existing ones.
CREATE OR REPLACE TABLE trips
(
    trip_id             UInt32,
    pickup_datetime     DateTime,
    dropoff_datetime    DateTime,
    pickup_longitude    Nullable(Float64),
    pickup_latitude     Nullable(Float64),
    dropoff_longitude   Nullable(Float64),
    dropoff_latitude    Nullable(Float64),
    passenger_count     UInt8,
    trip_distance       Float32,
    fare_amount         Float32,
    extra               Float32,
    tip_amount          Float32,
    tolls_amount        Float32,
    total_amount        Float32,
    payment_type        Enum('CSH' = 1, 'CRE' = 2, 'NOC' = 3, 'DIS' = 4, 'UNK' = 5),
    pickup_ntaname      LowCardinality(String),
    dropoff_ntaname     LowCardinality(String)
)
ENGINE = MergeTree
PRIMARY KEY (pickup_datetime, dropoff_datetime);

INSERT INTO trips
SELECT
    trip_id, pickup_datetime, dropoff_datetime, pickup_longitude,
    pickup_latitude, dropoff_longitude, dropoff_latitude,
    passenger_count, trip_distance, fare_amount, extra, tip_amount,
    tolls_amount, total_amount, payment_type, pickup_ntaname,
    dropoff_ntaname
FROM s3(
    'https://datasets-documentation.s3.eu-west-3.amazonaws.com/nyc-taxi/trips_{0..2}.gz',
    'TabSeparatedWithNames'
);

SELECT
    count()              AS rows,
    min(pickup_datetime) AS earliest,
    max(pickup_datetime) AS latest
FROM trips;

-- How much space did all those rows take after compression?
SELECT formatReadableSize(total_bytes) AS on_disk
FROM system.tables
WHERE database = currentDatabase() AND name = 'trips';
