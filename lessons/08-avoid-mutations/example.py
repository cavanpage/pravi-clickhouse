"""Lesson 08 · Avoid mutations (Python edition).

Models updates and deletes the ClickHouse way: insert new versions into a
ReplacingMergeTree and resolve them with FINAL, instead of issuing UPDATE/DELETE
mutations.

Run:  python lessons/08-avoid-mutations/example.py
"""
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client, show  # noqa: E402

COLS = ["id", "name", "plan", "is_deleted", "updated_at"]


def dt(s: str) -> datetime:
    return datetime.strptime(s, "%Y-%m-%d %H:%M:%S")


def main() -> None:
    client.command("DROP TABLE IF EXISTS users")
    client.command("""
        CREATE TABLE users
        (id UInt64, name String, plan LowCardinality(String),
         is_deleted UInt8 DEFAULT 0, updated_at DateTime)
        ENGINE = ReplacingMergeTree(updated_at, is_deleted)
        ORDER BY id
    """)

    client.insert("users", [
        [1, "Ada", "free", 0, dt("2026-01-01 00:00:00")],
        [2, "Babb", "free", 0, dt("2026-01-01 00:00:00")],
        [3, "Chen", "pro", 0, dt("2026-01-01 00:00:00")],
    ], column_names=COLS)

    # "Update" Ada to pro: insert a newer version. No mutation.
    client.insert("users", [[1, "Ada", "pro", 0, dt("2026-06-01 00:00:00")]],
                  column_names=COLS)

    # "Delete" Babb: insert a tombstone.
    client.insert("users", [[2, "Babb", "free", 1, dt("2026-06-10 00:00:00")]],
                  column_names=COLS)

    print("Raw rows (every inserted version is still present):")
    show("SELECT id, name, plan, is_deleted, updated_at FROM users ORDER BY id, updated_at")

    print("\nResolved view (FINAL = latest version per id, excluding deleted):")
    show("SELECT id, name, plan FROM users FINAL WHERE is_deleted = 0 ORDER BY id")

    print("\nNo UPDATE or DELETE was issued — only inserts. ClickHouse resolves "
          "the current state at read time with FINAL.")


if __name__ == "__main__":
    main()
