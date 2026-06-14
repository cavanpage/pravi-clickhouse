"""Lesson 01 · Primary keys (Python edition).

Builds two tables that differ only in ORDER BY, runs the same query against
each, and reports how many rows ClickHouse read — straight from the query
summary the driver returns.

Run:  python lessons/01-primary-keys/example.py
Prereq:  make load-data
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client  # noqa: E402

NEIGHBOURHOOD = "Midtown-Midtown South"

SCHEMAS = {
    "trips_by_nta": "ORDER BY (pickup_ntaname, pickup_datetime)",
    "trips_by_time": "ORDER BY (pickup_datetime)",
}


def build(table: str, order_by: str) -> None:
    client.command(f"DROP TABLE IF EXISTS {table}")
    client.command(f"""
        CREATE TABLE {table}
        (
            pickup_datetime  DateTime,
            pickup_ntaname   LowCardinality(String),
            passenger_count  UInt8,
            total_amount     Float32
        )
        ENGINE = MergeTree
        {order_by}
    """)
    client.command(f"""
        INSERT INTO {table}
        SELECT pickup_datetime, pickup_ntaname, passenger_count, total_amount
        FROM trips
    """)


def measure(table: str) -> None:
    result = client.query(
        f"""
        SELECT count() AS trips, round(avg(total_amount), 2) AS avg_fare
        FROM {table}
        WHERE pickup_ntaname = {{nta:String}}
        """,
        parameters={"nta": NEIGHBOURHOOD},
    )
    read_rows = int((result.summary or {}).get("read_rows", 0))
    trips, avg_fare = result.result_rows[0]
    print(
        f"{table:>14}: {trips:>8,} trips, avg ${avg_fare:<6} "
        f"| read_rows = {read_rows:>10,}"
    )


def main() -> None:
    for table, order_by in SCHEMAS.items():
        build(table, order_by)

    print(f"\nQuery: trips & avg fare in '{NEIGHBOURHOOD}'\n")
    for table in SCHEMAS:
        measure(table)
    print(
        "\nThe table ordered by (pickup_ntaname, ...) reads far fewer rows: its "
        "sparse index can skip granules for other neighbourhoods."
    )


if __name__ == "__main__":
    main()
