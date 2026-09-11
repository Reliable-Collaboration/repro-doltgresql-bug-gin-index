# DoltgreSQL 1.3.1: GIN indexes are refused with "index method gin is not yet supported"

On DoltgreSQL 1.3.1, `CREATE INDEX ... USING gin` fails and creates no index, whether the index is on an
integer array column, a `jsonb` column or a full-text expression:

```
ERROR:  index method gin is not yet supported
```

PostgreSQL 18.6 creates the same index, and `pg_indexes` lists it afterwards.

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the images.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-gin-index.git
cd repro-doltgresql-bug-gin-index
./repro.sh
```

`repro.sh` starts PostgreSQL 18.6 and DoltgreSQL 1.3.1 in two throwaway containers, waits until both
accept connections, runs [`repro.sql`](repro.sql) on each with the `psql` client inside its container,
prints the two outputs side by side, and removes the containers. It exits 0 when DoltgreSQL's output is
identical to PostgreSQL's, and 1 when it differs.

To try another DoltgreSQL release, name its image:

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory. PostgreSQL first:

```sh
docker run -d --name repro-doltgresql-bug-gin-index-postgres -e POSTGRES_PASSWORD=password postgres:18.6-bookworm
docker cp repro.sql repro-doltgresql-bug-gin-index-postgres:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-gin-index-postgres psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f repro-doltgresql-bug-gin-index-postgres
```

Then DoltgreSQL:

```sh
docker run -d --name repro-doltgresql-bug-gin-index-doltgresql -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql repro-doltgresql-bug-gin-index-doltgresql:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-gin-index-doltgresql psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f repro-doltgresql-bug-gin-index-doltgresql
```

If `docker exec` answers that the connection was refused, the server is still starting: wait a few
seconds and run it again.

## The test

[`repro.sql`](repro.sql):

```sql
-- A table with an integer array column.
CREATE TABLE t (id int PRIMARY KEY, tags int[]);

-- A GIN index on the array column.
CREATE INDEX t_tags_idx ON t USING gin (tags);

-- The table's indexes afterwards.
SELECT indexdef FROM pg_indexes
WHERE tablename = 't' ORDER BY indexname;
```

## Expected behavior

The index is created, and `pg_indexes` lists it next to the primary key's index. This is what
PostgreSQL 18.6 does:

```
CREATE INDEX t_tags_idx ON t USING gin (tags);
CREATE INDEX
-- The table's indexes afterwards.
SELECT indexdef FROM pg_indexes
WHERE tablename = 't' ORDER BY indexname;
                        indexdef                         
---------------------------------------------------------
 CREATE UNIQUE INDEX t_pkey ON public.t USING btree (id)
 CREATE INDEX t_tags_idx ON public.t USING gin (tags)
(2 rows)
```

## Actual behavior

The `CREATE INDEX` fails, and `pg_indexes` lists only the primary key's index. This is what
DoltgreSQL 1.3.1 does:

```
CREATE INDEX t_tags_idx ON t USING gin (tags);
psql:/tmp/repro.sql:5: ERROR:  index method gin is not yet supported
-- The table's indexes afterwards.
SELECT indexdef FROM pg_indexes
WHERE tablename = 't' ORDER BY indexname;
                        indexdef                         
---------------------------------------------------------
 CREATE UNIQUE INDEX t_pkey ON public.t USING btree (id)
(1 row)
```

## Side by side

The full output of `./repro.sh`. A line wider than its column is cut off at the column's edge, as
DoltgreSQL's error is here; the whole error is under Actual behavior.

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851

Left: PostgreSQL. Right: DoltgreSQL. Lines that differ are marked with |.

-- A table with an integer array column.                      -- A table with an integer array column.
CREATE TABLE t (id int PRIMARY KEY, tags int[]);              CREATE TABLE t (id int PRIMARY KEY, tags int[]);
CREATE TABLE                                                  CREATE TABLE
-- A GIN index on the array column.                           -- A GIN index on the array column.
CREATE INDEX t_tags_idx ON t USING gin (tags);                CREATE INDEX t_tags_idx ON t USING gin (tags);
CREATE INDEX                                                | psql:/tmp/repro.sql:5: ERROR:  index method gin is not yet 
-- The table's indexes afterwards.                            -- The table's indexes afterwards.
SELECT indexdef FROM pg_indexes                               SELECT indexdef FROM pg_indexes
WHERE tablename = 't' ORDER BY indexname;                     WHERE tablename = 't' ORDER BY indexname;
                        indexdef                                                      indexdef                         
---------------------------------------------------------     ---------------------------------------------------------
 CREATE UNIQUE INDEX t_pkey ON public.t USING btree (id)       CREATE UNIQUE INDEX t_pkey ON public.t USING btree (id)
 CREATE INDEX t_tags_idx ON public.t USING gin (tags)       | (1 row)
(2 rows)                                                    <


Result: DoltgreSQL's output differs from PostgreSQL's on 2 line(s), marked with |.
```

## Other observations

Each was run on the same two images with the same `psql` command:

- A GIN index on a `jsonb` column fails with the same error, with or without the `jsonb_path_ops`
  operator class, and so does a GIN index on a table that already holds rows. PostgreSQL creates them.
- A GIN index over a full-text expression, `USING gin (to_tsvector('english', body))` on a `text`
  column, fails with the same error; PostgreSQL creates it. On its own,
  `SELECT to_tsvector('english', 'fat cats')` answers `function: 'to_tsvector' not found`.
- The index method is refused before the table is looked up: `CREATE INDEX nope_gin ON no_such_table
  USING gin (c)` answers `index method gin is not yet supported`, where PostgreSQL answers
  `relation "no_such_table" does not exist`.
- A btree index on the same kinds of column, `CREATE INDEX ... (tags)` on an `int[]` column and
  `CREATE INDEX ... (doc)` on a `jsonb` column, is created on both engines.
- `USING hash`, `USING brin` and `USING spgist` fail the same way (`index method hash is not yet
  supported`, and so on); PostgreSQL creates all three. An unknown method, `USING nonsense`, answers
  `index method nonsense is not yet supported`, where PostgreSQL answers
  `access method "nonsense" does not exist`.
- `SELECT amname FROM pg_am ORDER BY 1` answers the same seven rows on both engines, `gin` among them.
- The containment operators a GIN index serves fail too: `tags @> ARRAY[1]` on an `int[]` column answers
  `operator does not exist: integer[] @> integer[]`, and `doc @> '{"a": 1}'` on a `jsonb` column answers
  `JSON contains is not yet supported`. `doc ? 'b'` answers the same row on both engines.

## Environment

- DoltgreSQL 1.3.1, the newest release when this was written: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`. Its bundled `psql` is 17.11.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`. Its `psql` is 18.6.
- Reproduced on 2026-09-11 (UTC) with Docker 29.7.2 on Linux x86_64 (WSL 2).
