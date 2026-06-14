"""Lesson 04 · JOINs (Python edition).

Builds a small dimension table, runs a correct big-LEFT/small-RIGHT join, then
the equivalent dictionary lookup, and compares timing/memory from the query
summary.

Run:  python lessons/04-joins/example.py
Prereq:  make load-data
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from ch import client  # noqa: E402


def setup() -> None:
    client.command("DROP DICTIONARY IF EXISTS nta_dict")
    client.command("DROP TABLE IF EXISTS neighbourhoods")
    client.command("""
        CREATE TABLE neighbourhoods
        (name LowCardinality(String), borough LowCardinality(String), is_airport UInt8)
        ENGINE = MergeTree ORDER BY name
    """)
    client.command("""
        INSERT INTO neighbourhoods
        SELECT pickup_ntaname,
               transform(cityHash64(pickup_ntaname) % 5, [0,1,2,3,4],
                   ['Manhattan','Brooklyn','Queens','Bronx','Staten Island'],
                   'Unknown'),
               pickup_ntaname ILIKE '%airport%'
        FROM trips GROUP BY pickup_ntaname
    """)
    client.command("""
        CREATE DICTIONARY nta_dict
        (name String, borough String, is_airport UInt8)
        PRIMARY KEY name
        SOURCE(CLICKHOUSE(TABLE 'neighbourhoods' DB 'learn' USER 'learner' PASSWORD 'learn'))
        LIFETIME(MIN 600 MAX 900)
        LAYOUT(COMPLEX_KEY_HASHED())
    """)


def main() -> None:
    setup()
    print("Both queries below produce the same answer; one joins, one doesn't.\n")

    print("JOIN result:")
    join = client.query("""
        SELECT n.borough, count() AS trips
        FROM trips AS t
        INNER JOIN neighbourhoods AS n ON t.pickup_ntaname = n.name
        GROUP BY n.borough ORDER BY trips DESC LIMIT 3
    """)
    for row in join.result_rows:
        print(f"  {row[0]:<16} {row[1]:>10,}")

    print("\ndictGet() result (no join):")
    dic = client.query("""
        SELECT dictGet('nta_dict','borough', pickup_ntaname) AS borough, count() AS trips
        FROM trips GROUP BY borough ORDER BY trips DESC LIMIT 3
    """)
    for row in dic.result_rows:
        print(f"  {row[0]:<16} {row[1]:>10,}")

    print("\nFor small, static lookups prefer the dictionary: in-memory, no "
          "per-query hash build.")


if __name__ == "__main__":
    main()
