# Python examples

Each lesson has a SQL file (`lesson.sql`) and a Python counterpart
(`example.py`). The SQL teaches the ClickHouse feature; the Python shows how
you'd use it from an application with the official
[`clickhouse-connect`](https://clickhouse.com/docs/integrations/python) driver.

## Setup

```bash
cd python
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

Connection settings are read from the repo-root `.env` (copy `.env.example`),
falling back to the docker-compose defaults (`learner` / `learn` on
`localhost:8123`).

## Smoke test

With ClickHouse running (`make up` from the repo root):

```bash
python ch.py
```

You should see the server version and time.

## Running a lesson's Python example

```bash
python ../lessons/06-insert-strategy/example.py
```

`ch.py` is on the path because each `example.py` adds the `python/` directory to
`sys.path`. The shared helper gives you:

- `connect(database=None)` — a fresh client
- `client` — a ready-made client
- `show("SELECT ...")` — run a query and print it as a DataFrame, plus the
  number of rows ClickHouse actually read (the metric most lessons care about)
