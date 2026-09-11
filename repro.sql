-- A table with an integer array column.
CREATE TABLE t (id int PRIMARY KEY, tags int[]);

-- A GIN index on the array column.
CREATE INDEX t_tags_idx ON t USING gin (tags);

-- The table's indexes afterwards.
SELECT indexdef FROM pg_indexes
WHERE tablename = 't' ORDER BY indexname;
