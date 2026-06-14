"""Lesson 07 · Data skipping indices (Python edition).

Runs the same filtered query with skip indices ON and OFF and prints how many
rows ClickHouse read each way — the proof of whether the index helps.

Run:  python lessons/07-skipping-indices/example.py
Prereq:  make load-data
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client  # noqa: E402


def setup() -> None:
    client.command("DROP TABLE IF EXISTS trips_skip")
    client.command("""
        CREATE TABLE trips_skip
        (
            pickup_datetime DateTime,
            passenger_count UInt8,
            trip_distance   Float32,
            total_amount    Float32,
            INDEX idx_distance trip_distance TYPE minmax GRANULARITY 4,
            INDEX idx_pax passenger_count TYPE set(16) GRANULARITY 4
        )
        ENGINE = MergeTree ORDER BY pickup_datetime
    """)
    client.command("""
        INSERT INTO trips_skip
        SELECT pickup_datetime, passenger_count, trip_distance, total_amount
        FROM trips
    """)
    client.command("ALTER TABLE trips_skip MATERIALIZE INDEX idx_distance")


def read_rows(use_index: bool) -> int:
    r = client.query(
        "SELECT count() FROM trips_skip WHERE trip_distance > 50",
        settings={"use_skip_indexes": 1 if use_index else 0},
    )
    return int((r.summary or {}).get("read_rows", 0))


def main() -> None:
    setup()
    on = read_rows(True)
    off = read_rows(False)
    print("Query: SELECT count() FROM trips_skip WHERE trip_distance > 50\n")
    print(f"  skip index ON : read {on:>12,} rows")
    print(f"  skip index OFF: read {off:>12,} rows")
    if on < off:
        print(f"\nThe minmax index skipped {(off - on) / off:.0%} of the rows "
              "because long trips cluster together on disk.")
    else:
        print("\nNo improvement here — the values weren't clustered enough to "
              "skip blocks. (That's a real and useful result: measure before "
              "adding indices.)")


if __name__ == "__main__":
    main()
