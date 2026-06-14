"""Shared ClickHouse connection helper for the Python lessons.

Every example does `from ch import client` (or `connect()`), so connection
details live in exactly one place. Settings come from environment variables /
the repo's .env file, matching docker-compose.yml.

Usage:
    from ch import client, show
    show("SELECT version()")
"""
from __future__ import annotations

import os
from pathlib import Path

import clickhouse_connect
from dotenv import load_dotenv

# Load the repo-root .env if it exists (one directory up from python/).
load_dotenv(Path(__file__).resolve().parent.parent / ".env")


def connect(database: str | None = None):
    """Return a fresh clickhouse-connect client.

    Uses the HTTP interface (port 8123). The native protocol (9000) is faster
    but clickhouse-connect speaks HTTP, which is the most portable choice and
    the one ClickHouse Cloud exposes.
    """
    return clickhouse_connect.get_client(
        host=os.getenv("CLICKHOUSE_HOST", "localhost"),
        port=int(os.getenv("CLICKHOUSE_HTTP_PORT", "8123")),
        username=os.getenv("CLICKHOUSE_USER", "learner"),
        password=os.getenv("CLICKHOUSE_PASSWORD", "learn"),
        database=database or os.getenv("CLICKHOUSE_DB", "learn"),
    )


# A ready-to-use client for quick scripts.
client = connect()


def show(query: str, **kwargs) -> None:
    """Run a SELECT and pretty-print it as a pandas DataFrame.

    Also prints how many rows ClickHouse actually read — the number that
    matters in almost every performance lesson here.
    """
    result = client.query(query, **kwargs)
    df = result.result_rows
    import pandas as pd

    frame = pd.DataFrame(df, columns=result.column_names)
    print(frame.to_string(index=False))
    summary = result.summary or {}
    if "read_rows" in summary:
        print(
            f"\n[read {int(summary['read_rows']):,} rows / "
            f"{int(summary.get('read_bytes', 0)):,} bytes]"
        )


if __name__ == "__main__":
    # Smoke test: `python ch.py`
    show("SELECT version() AS clickhouse_version, now() AS server_time")
