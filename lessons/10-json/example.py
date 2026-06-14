"""Lesson 10 · JSON & semi-structured data (Python edition).

Inserts nested JSON events (each a slightly different shape), then queries typed
and dynamic paths and inspects which paths ClickHouse actually stored.

clickhouse-connect accepts JSON values as Python dicts/JSON strings; here we
insert JSON text rows for clarity.

Run:  python lessons/10-json/example.py
Requires ClickHouse 24.8+ (this repo pins 26.3).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client, show  # noqa: E402


def main() -> None:
    client.command("DROP TABLE IF EXISTS app_events")
    client.command("""
        CREATE TABLE app_events
        (
            id UInt64,
            ts DateTime DEFAULT now(),
            data JSON(
                user.id UInt32,
                user.tier LowCardinality(String),
                SKIP debug,
                SKIP REGEXP '^tmp_',
                max_dynamic_paths = 256
            )
        )
        ENGINE = MergeTree ORDER BY id
    """)

    # Insert via INSERT ... VALUES so the JSON strings are parsed server-side.
    client.command("""
        INSERT INTO app_events (id, data) VALUES
        (1, '{"user":{"id":123,"tier":"pro"},"action":"login","ip":"10.0.0.1"}'),
        (2, '{"user":{"id":456,"tier":"free"},"action":"purchase","amount":49.99}'),
        (3, '{"user":{"id":123,"tier":"pro"},"action":"logout","debug":"x","tmp_q":1}')
    """)

    print("Events grouped by typed JSON paths (data.user.id / data.user.tier):\n")
    show("""
        SELECT data.user.id AS user_id, data.user.tier AS tier, count() AS events
        FROM app_events
        GROUP BY user_id, tier
        ORDER BY events DESC
    """)

    print("\nDynamic paths, cast on read:\n")
    show("""
        SELECT id,
               data.action::String AS action,
               data.amount::Nullable(Float64) AS amount
        FROM app_events ORDER BY id
    """)

    print("\nPaths ClickHouse actually stored (SKIP'd 'debug'/'tmp_q' are gone):\n")
    show("SELECT DISTINCT arrayJoin(JSONAllPaths(data)) AS stored_path "
         "FROM app_events ORDER BY stored_path")


if __name__ == "__main__":
    main()
