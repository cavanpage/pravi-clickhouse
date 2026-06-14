"""Lesson 02 · Data types (Python edition).

Builds a naive vs. optimized schema, loads identical data, and prints the
compressed size of each so you can see the savings as a ratio.

Run:  python lessons/02-data-types/example.py
Prereq:  make load-data
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client  # noqa: E402

NAIVE = """
CREATE TABLE trips_naive (
    pickup_datetime  DateTime,
    passenger_count  Int64,
    payment_type     String,
    pickup_ntaname   Nullable(String),
    total_amount     Float64
) ENGINE = MergeTree ORDER BY pickup_datetime
"""

TYPED = """
CREATE TABLE trips_typed (
    pickup_datetime  DateTime CODEC(DoubleDelta, ZSTD(1)),
    passenger_count  UInt8,
    payment_type     Enum('CSH'=1,'CRE'=2,'NOC'=3,'DIS'=4,'UNK'=5),
    pickup_ntaname   LowCardinality(String),
    total_amount     Float32 CODEC(ZSTD(1))
) ENGINE = MergeTree ORDER BY pickup_datetime
"""

COLUMNS = ("pickup_datetime, passenger_count, payment_type, "
           "pickup_ntaname, total_amount")


def build(table: str, ddl: str) -> None:
    client.command(f"DROP TABLE IF EXISTS {table}")
    client.command(ddl)
    client.command(f"INSERT INTO {table} SELECT {COLUMNS} FROM trips")


def compressed_bytes(table: str) -> int:
    return int(client.query(
        """
        SELECT sum(data_compressed_bytes)
        FROM system.columns
        WHERE database = currentDatabase() AND table = {t:String}
        """,
        parameters={"t": table},
    ).result_rows[0][0])


def main() -> None:
    build("trips_naive", NAIVE)
    build("trips_typed", TYPED)

    naive = compressed_bytes("trips_naive")
    typed = compressed_bytes("trips_typed")

    print(f"trips_naive (String/Nullable/Int64): {naive / 1e6:8.1f} MB")
    print(f"trips_typed (LowCardinality/Enum/codecs): {typed / 1e6:5.1f} MB")
    print(f"\nThe typed schema is {naive / typed:.1f}x smaller — same data.")


if __name__ == "__main__":
    main()
