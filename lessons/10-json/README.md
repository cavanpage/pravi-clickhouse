# 10 · JSON & semi-structured data

**Goal:** use ClickHouse's modern native `JSON` type for semi-structured data —
and know when a plain `String` is the better call.

Docs: [Use JSON where appropriate](https://clickhouse.com/docs/best-practices/use-json-where-appropriate) ·
[JSON type reference](https://clickhouse.com/docs/sql-reference/data-types/newjson) ·
[Working with JSON](https://clickhouse.com/docs/integrations/data-formats/json/overview)

## The native JSON type

ClickHouse has a true columnar `JSON` type. It doesn't store a blob of text —
it **decomposes each path into its own subcolumn**, stored and compressed
independently, with the type(s) seen for that path tracked dynamically. So
`SELECT data.user.id` reads only that one path's column, just like a regular
column. You get schema flexibility *and* columnar performance.

```sql
CREATE TABLE events
(
    id   UInt64,
    data JSON
)
ENGINE = MergeTree ORDER BY id;

INSERT INTO events VALUES
    (1, '{"user": {"id": 123, "tier": "pro"}, "action": "login"}');

SELECT data.user.id, data.action FROM events;   -- dot-path access
```

## Make it fast with hints

A bare `JSON` is convenient but the engine has to discover everything. Help it:

```sql
data JSON(
    user.id UInt32,          -- typed hint: materialize this path as UInt32
    timestamp DateTime,
    SKIP internal.debug,     -- never store this path
    SKIP REGEXP '^tmp_',     -- skip paths matching a pattern
    max_dynamic_paths = 256  -- cap separately-stored paths
)
```

- **Typed hints** (`some.path Type`) — for paths you query a lot. Stores them as
  that concrete type: smaller, faster, no per-query casting.
- **`SKIP` / `SKIP REGEXP`** — drop paths you never need so they don't bloat
  storage.
- **`max_dynamic_paths`** — bounds how many distinct paths get their own
  subcolumn; the rest go to a shared structure. Keep it sane.

Querying a dynamic (un-hinted) path returns a `Dynamic` type — cast it when you
need a concrete type: `data.action::String`, `data.count::UInt32`.

## Best practices

- **Hint the paths you know and query.** Reserve dynamic paths for the genuinely
  unpredictable parts.
- **Keep path counts bounded.** Thousands of distinct paths hurt; the docs
  suggest staying well under the limits (≲ a few hundred is comfortable, 1024 is
  the remote default cap).
- **Don't use JSON for opaque blobs.** If you never query inside it (you just
  store and return it whole), a plain `String` compresses fine and is simpler.
- **Don't reach for JSON to dodge schema design.** If your data is actually
  regular, explicit typed columns (lesson 02) are still the fastest, smallest
  option. JSON is for genuinely variable/sparse structures.

## What you'll do in `lesson.sql`
Create a `JSON` column with typed hints and SKIPs, insert nested events, query
paths with dot notation and casts, inspect which subcolumns/paths exist, and
compare against storing the same payload as a `String`.
