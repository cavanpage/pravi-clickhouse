# 02 · Data types

**Goal:** pick types that compress well and query fast. In a column store, the
right type is one of the biggest free wins you'll ever get.

Docs: [Select data types](https://clickhouse.com/docs/best-practices/select-data-types) ·
[LowCardinality](https://clickhouse.com/docs/sql-reference/data-types/lowcardinality) ·
[Codecs](https://clickhouse.com/docs/sql-reference/statements/create/table#column_compression_codec)

## Why types matter more here

Each column is stored and compressed independently. A tighter type means fewer
bytes on disk, fewer bytes read per query, and better compression ratios. The
rules:

### 1. Use the smallest correct numeric type
`UInt8` (0–255) vs `Int64` is an 8× difference before compression. Need no
negatives? Use the unsigned variant. Don't store numbers as `String`.

### 2. `LowCardinality(String)` for columns with few distinct values
Under ~10,000 distinct values (think status, country, event_type), wrap the type
in `LowCardinality`. ClickHouse dictionary-encodes it: store each distinct value
once, then small integer references. Massive shrink, faster `GROUP BY`.

### 3. `Enum` for a fixed, known set
When the set of values is fixed and known (`'CSH','CRE','NOC',...`), `Enum8`/
`Enum16` stores a 1–2 byte integer *and* validates inserts — an unknown value is
an error, not a silent typo.

### 4. Avoid `Nullable` unless you truly need NULL
`Nullable(T)` adds a hidden `UInt8` bitmap column to mark nulls, costing space
and blocking some optimizations. Prefer a sentinel default (`0`, `''`) when
"missing" and "zero" mean the same thing for you.

### 5. Coarsest date/time that works
`Date` (2 bytes) over `DateTime` (4 bytes) over `DateTime64` (8 bytes). Only use
sub-second `DateTime64` if you genuinely need it.

### 6. `FixedString(N)` only for truly fixed-width data
Country codes, currency codes, hashes. For anything variable, `LowCardinality
(String)` or `String` is better.

### 7. Reach for codecs on the right columns
Beyond the table-wide compression, per-column **codecs** exploit structure:
- `Delta` / `DoubleDelta` + a compressor for slowly-changing or monotonic
  numbers (timestamps, counters): `DateTime CODEC(DoubleDelta, ZSTD)`.
- `Gorilla` for floating-point gauges (sensor readings).
- `ZSTD(level)` as a stronger general compressor than the default `LZ4`.

## What you'll do in `lesson.sql`

Create the same logical table two ways — a naive "everything is a String /
Nullable / Int64" version and an optimized version — load identical data, and
compare on-disk size with `system.columns`. The difference is dramatic.
