"""Lesson 09 · Avoid OPTIMIZE FINAL (Python edition).

Loads a ReplacingMergeTree full of duplicate versions, then gets the current
value per key three ways and compares what each one read:
  A) read-time aggregation with argMax  (no rewrite)
  B) SELECT ... FINAL                    (resolve at read time)
  C) OPTIMIZE TABLE ... FINAL            (rewrites the whole table)

Run:  python lessons/09-avoid-optimize-final/example.py
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client  # noqa: E402


def setup() -> None:
    client.command("DROP TABLE IF EXISTS prices")
    client.command("""
        CREATE TABLE prices (sku UInt32, price Float64, version DateTime)
        ENGINE = ReplacingMergeTree(version) ORDER BY sku
    """)
    for month in range(1, 6):
        client.command(
            f"INSERT INTO prices SELECT number, {9 + month} + number % 90, "
            f"'2026-0{month}-01 00:00:00' FROM numbers(10000)"
        )


def run(label: str, query: str) -> None:
    t0 = time.perf_counter()
    r = client.query(query)
    elapsed = (time.perf_counter() - t0) * 1000
    read = int((r.summary or {}).get("read_rows", 0))
    print(f"{label:<26} read {read:>9,} rows  in {elapsed:6.1f} ms")


def main() -> None:
    setup()
    raw = client.query("SELECT count() FROM prices").result_rows[0][0]
    print(f"Table has {raw:,} raw rows (5 versions x 10,000 SKUs).\n")

    run("A) argMax aggregation",
        "SELECT sku, argMax(price, version) FROM prices GROUP BY sku")
    run("B) SELECT ... FINAL",
        "SELECT sku, price FROM prices FINAL")

    # C) OPTIMIZE FINAL rewrites the whole table. command() returns no summary,
    # so just time it.
    t0 = time.perf_counter()
    client.command("OPTIMIZE TABLE prices FINAL")
    print(f"{'C) OPTIMIZE TABLE FINAL':<26} rewrote the whole table "
          f"in {(time.perf_counter() - t0) * 1000:6.1f} ms")

    print("\nA and B answer the question without rewriting anything. C rewrites "
          "every part — and the next insert undoes it. Prefer A or B.")


if __name__ == "__main__":
    main()
