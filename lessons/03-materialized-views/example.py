"""Lesson 03 · Materialized views (Python edition).

Sets up an incremental MV with an AggregatingMergeTree target, backfills it,
then demonstrates that a fresh insert into the source table flows through to the
pre-aggregated target automatically.

Run:  python lessons/03-materialized-views/example.py
Prereq:  make load-data
"""
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client, show  # noqa: E402


def setup() -> None:
    client.command("DROP TABLE IF EXISTS trips_daily_mv")
    client.command("DROP TABLE IF EXISTS trips_daily_stats")

    client.command("""
        CREATE TABLE trips_daily_stats
        (
            day            Date,
            pickup_ntaname LowCardinality(String),
            trips_state    AggregateFunction(count),
            avg_fare_state AggregateFunction(avg, Float32)
        )
        ENGINE = AggregatingMergeTree
        ORDER BY (pickup_ntaname, day)
    """)

    client.command("""
        CREATE MATERIALIZED VIEW trips_daily_mv TO trips_daily_stats AS
        SELECT
            toDate(pickup_datetime) AS day,
            pickup_ntaname,
            countState()           AS trips_state,
            avgState(total_amount) AS avg_fare_state
        FROM trips
        GROUP BY day, pickup_ntaname
    """)

    # Backfill existing data (the MV only triggers on future inserts).
    client.command("""
        INSERT INTO trips_daily_stats
        SELECT toDate(pickup_datetime), pickup_ntaname,
               countState(), avgState(total_amount)
        FROM trips
        GROUP BY toDate(pickup_datetime), pickup_ntaname
    """)


def main() -> None:
    setup()

    print("Top neighbourhoods from the pre-aggregated MV target:\n")
    show("""
        SELECT pickup_ntaname,
               countMerge(trips_state) AS trips,
               round(avgMerge(avg_fare_state), 2) AS avg_fare
        FROM trips_daily_stats
        GROUP BY pickup_ntaname
        ORDER BY trips DESC
        LIMIT 5
    """)

    print("\nInserting one new trip into the SOURCE table...")
    client.insert(
        "trips",
        [[datetime(2026, 6, 14, 12, 0), datetime(2026, 6, 14, 12, 10), 2, 3.0,
          30.0, "CRE", "PythonTest-NTA", "PythonTest-NTA", 999999998]],
        column_names=["pickup_datetime", "dropoff_datetime", "passenger_count",
                      "trip_distance", "total_amount", "payment_type",
                      "pickup_ntaname", "dropoff_ntaname", "trip_id"],
    )

    print("...and reading it back from the MV target (no manual recompute):\n")
    show("""
        SELECT pickup_ntaname, countMerge(trips_state) AS trips
        FROM trips_daily_stats
        WHERE pickup_ntaname = 'PythonTest-NTA'
        GROUP BY pickup_ntaname
    """)


if __name__ == "__main__":
    main()
