"""Lesson 11 · Time series (Python edition).

Generates a synthetic multi-sensor metrics table, then demonstrates the
time-series toolkit: bucketing, gap filling with WITH FILL, a moving average
window, and an ASOF JOIN to align readings with setpoint changes.

Run:  python lessons/11-time-series/example.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client, show  # noqa: E402


def setup() -> None:
    client.command("DROP TABLE IF EXISTS metrics")
    client.command("""
        CREATE TABLE metrics
        (
            ts        DateTime CODEC(DoubleDelta, ZSTD(1)),
            sensor_id LowCardinality(String),
            value     Float64  CODEC(Gorilla, ZSTD(1))
        )
        ENGINE = MergeTree
        PARTITION BY toYYYYMM(ts)
        ORDER BY (sensor_id, ts)
        -- wide parts so per-column codec sizes are visible in system.columns
        SETTINGS min_bytes_for_wide_part = 0
    """)
    # sensor_a with a deliberate gap (minutes 600..720), plus sensor_b.
    client.command("""
        INSERT INTO metrics
        SELECT toDateTime('2026-06-01 00:00:00') + toIntervalMinute(number),
               'sensor_a', 20 + 5 * sin(number / 120.0) + (rand() % 100) / 100.0
        FROM numbers(2880)
        WHERE number < 600 OR number > 720
    """)
    client.command("""
        INSERT INTO metrics
        SELECT toDateTime('2026-06-01 00:00:00') + toIntervalMinute(number),
               'sensor_b', 50 + 10 * cos(number / 90.0) + (rand() % 100) / 100.0
        FROM numbers(2880)
    """)


def main() -> None:
    setup()

    print("Codec compression for the metrics columns:\n")
    show("""
        SELECT name AS column, type,
               formatReadableSize(data_compressed_bytes) AS compressed,
               formatReadableSize(data_uncompressed_bytes) AS uncompressed
        FROM system.columns
        WHERE database = currentDatabase() AND table = 'metrics'
        ORDER BY name
    """)

    print("\nsensor_a hourly averages WITHOUT gap filling (note missing hours):\n")
    show("""
        SELECT toStartOfInterval(ts, INTERVAL 1 HOUR) AS hour, round(avg(value),2) AS v
        FROM metrics WHERE sensor_id = 'sensor_a'
        GROUP BY hour ORDER BY hour LIMIT 14
    """)

    print("\nSame query WITH FILL + INTERPOLATE (every hour present):\n")
    show("""
        SELECT toStartOfInterval(ts, INTERVAL 1 HOUR) AS hour, round(avg(value),2) AS v
        FROM metrics WHERE sensor_id = 'sensor_a'
        GROUP BY hour
        ORDER BY hour WITH FILL STEP INTERVAL 1 HOUR
        INTERPOLATE (v AS v)
        LIMIT 14
    """)

    print("\n7-point moving average (window function) for sensor_b:\n")
    show("""
        SELECT ts, round(value, 2) AS value,
               round(avg(value) OVER (PARTITION BY sensor_id ORDER BY ts
                       ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS moving_avg_7
        FROM metrics WHERE sensor_id = 'sensor_b'
        ORDER BY ts LIMIT 8
    """)


if __name__ == "__main__":
    main()
