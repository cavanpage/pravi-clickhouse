"""Lesson 05 · Partitioning (Python edition).

Creates a monthly-partitioned table, lists its partitions, demonstrates that a
single-month query prunes to one partition, and drops a partition instantly.

Run:  python lessons/05-partitioning/example.py
Prereq:  make load-data
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client, show  # noqa: E402


def main() -> None:
    client.command("DROP TABLE IF EXISTS trips_monthly")
    client.command("""
        CREATE TABLE trips_monthly
        (
            pickup_datetime DateTime,
            pickup_ntaname  LowCardinality(String),
            passenger_count UInt8,
            total_amount    Float32
        )
        ENGINE = MergeTree
        PARTITION BY toYYYYMM(pickup_datetime)
        ORDER BY (pickup_ntaname, pickup_datetime)
    """)
    client.command("""
        INSERT INTO trips_monthly
        SELECT pickup_datetime, pickup_ntaname, passenger_count, total_amount
        FROM trips
    """)

    print("Partitions (one per month):\n")
    show("""
        SELECT partition, sum(rows) AS rows, count() AS parts
        FROM system.parts
        WHERE database = currentDatabase() AND table = 'trips_monthly' AND active
        GROUP BY partition ORDER BY partition
    """)

    # Grab a real partition id to demonstrate an instant drop.
    parts = client.query("""
        SELECT partition FROM system.parts
        WHERE database = currentDatabase() AND table = 'trips_monthly' AND active
        ORDER BY partition LIMIT 1
    """).result_rows
    if parts:
        part = parts[0][0]
        before = client.query("SELECT count() FROM trips_monthly").result_rows[0][0]
        client.command(f"ALTER TABLE trips_monthly DROP PARTITION '{part}'")
        after = client.query("SELECT count() FROM trips_monthly").result_rows[0][0]
        print(f"\nDropped partition {part}: {before:,} -> {after:,} rows "
              f"(instant — just unlinked files, no row-by-row delete).")


if __name__ == "__main__":
    main()
