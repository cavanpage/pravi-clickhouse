"""Lesson 06 · Insert strategy (Python edition) — the main demo.

Benchmarks three ingestion styles for the same 50,000 rows:
  1. many tiny inserts (the anti-pattern)
  2. one big batch       (the recommended default)
  3. async inserts       (server-side batching for when you can't batch)

Then demonstrates an idempotent retry being deduplicated.

Run:  python lessons/06-insert-strategy/example.py
"""
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client, connect  # noqa: E402

ROWS = 50_000
COLS = ["event_time", "user_id", "event_type", "value"]
# The native insert path expects real datetime objects for DateTime columns.
TS = datetime(2026, 6, 14, 0, 0, 0)


def make_rows(n: int):
    types = ["click", "view", "purchase"]
    return [
        [TS, i % 1000, types[i % 3], (i % 100) * 1.5]
        for i in range(n)
    ]


def fresh_table(name: str, dedup: bool = False) -> None:
    client.command(f"DROP TABLE IF EXISTS {name}")
    settings = " SETTINGS non_replicated_deduplication_window = 100" if dedup else ""
    client.command(f"""
        CREATE TABLE {name}
        (event_time DateTime, user_id UInt32,
         event_type LowCardinality(String), value Float64)
        ENGINE = MergeTree ORDER BY (event_type, event_time){settings}
    """)


def part_count(name: str) -> int:
    return int(client.query(
        "SELECT count() FROM system.parts WHERE database=currentDatabase() "
        "AND table={t:String} AND active", parameters={"t": name},
    ).result_rows[0][0])


def benchmark() -> None:
    rows = make_rows(ROWS)

    # 1. Many tiny inserts — chunks of 100 rows. This is what NOT to do.
    fresh_table("ins_tiny")
    t0 = time.perf_counter()
    for i in range(0, ROWS, 100):
        client.insert("ins_tiny", rows[i:i + 100], column_names=COLS)
    tiny = time.perf_counter() - t0

    # 2. One big batch — all rows in a single insert.
    fresh_table("ins_batch")
    t0 = time.perf_counter()
    client.insert("ins_batch", rows, column_names=COLS)
    batch = time.perf_counter() - t0

    # 3. Async inserts — small client-side inserts, server batches them.
    fresh_table("ins_async")
    aclient = connect()
    aclient.query("SET async_insert = 1, wait_for_async_insert = 1")
    t0 = time.perf_counter()
    for i in range(0, ROWS, 100):
        aclient.insert("ins_async", rows[i:i + 100], column_names=COLS,
                       settings={"async_insert": 1, "wait_for_async_insert": 1})
    asyn = time.perf_counter() - t0

    print(f"{'strategy':<22}{'time':>10}{'parts created':>16}")
    print("-" * 48)
    print(f"{'500 tiny inserts':<22}{tiny:>9.2f}s{part_count('ins_tiny'):>16}")
    print(f"{'1 big batch':<22}{batch:>9.2f}s{part_count('ins_batch'):>16}")
    print(f"{'500 async inserts':<22}{asyn:>9.2f}s{part_count('ins_async'):>16}")
    print("\nThe big batch is fastest and makes the fewest parts. Async inserts "
          "let you keep sending small payloads while the server does the "
          "batching for you.")


def idempotent_retry() -> None:
    print("\n--- Idempotent retry demo ---")
    fresh_table("ins_retry", dedup=True)
    batch = make_rows(1000)

    # Insert the same batch twice (simulating a client that retried after a
    # network blip). Identical block -> deduplicated.
    client.insert("ins_retry", batch, column_names=COLS)
    client.insert("ins_retry", batch, column_names=COLS)  # retry, same data/order

    count = client.query("SELECT count() FROM ins_retry").result_rows[0][0]
    print(f"Inserted a 1,000-row batch twice; table has {count:,} rows "
          f"({'deduplicated ✓' if count == 1000 else 'NOT deduplicated'}).")


def main() -> None:
    benchmark()
    idempotent_retry()


if __name__ == "__main__":
    main()
