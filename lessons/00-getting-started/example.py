"""Lesson 00 · Getting started (Python edition).

Same flow as lesson.sql, but driven from Python with clickhouse-connect:
create a table, insert rows, query, and inspect parts.

Run:  python lessons/00-getting-started/example.py
(after `pip install -r python/requirements.txt` and `make up`)
"""
import sys
from datetime import datetime
from pathlib import Path

# Make the shared helper in python/ importable from anywhere.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client, show  # noqa: E402


def dt(s: str) -> datetime:
    # The native insert path wants datetime objects for DateTime columns.
    return datetime.strptime(s, "%Y-%m-%d %H:%M:%S")


def main() -> None:
    print("Connected to ClickHouse", client.server_version, "\n")

    client.command("""
        CREATE OR REPLACE TABLE hello_events_py
        (
            event_time  DateTime,
            user_id     UInt32,
            event_type  LowCardinality(String),
            value       Float64
        )
        ENGINE = MergeTree
        ORDER BY (event_type, event_time)
    """)

    # insert() takes native Python rows — efficient and type-checked.
    rows = [
        [dt("2026-06-01 09:00:00"), 1, "click", 1.0],
        [dt("2026-06-01 09:01:00"), 2, "view", 0.0],
        [dt("2026-06-01 09:02:00"), 1, "purchase", 49.99],
        [dt("2026-06-01 09:03:00"), 3, "click", 1.0],
        [dt("2026-06-01 09:04:00"), 2, "purchase", 19.95],
    ]
    client.insert(
        "hello_events_py",
        rows,
        column_names=["event_time", "user_id", "event_type", "value"],
    )

    print("Events by type:")
    show("""
        SELECT event_type, count() AS events, round(sum(value), 2) AS total_value
        FROM hello_events_py
        GROUP BY event_type
        ORDER BY events DESC
    """)

    print("\nParts on disk:")
    show("""
        SELECT name, rows, formatReadableSize(bytes_on_disk) AS size
        FROM system.parts
        WHERE table = 'hello_events_py' AND database = currentDatabase()
    """)


if __name__ == "__main__":
    main()
