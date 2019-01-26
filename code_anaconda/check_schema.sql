-- schema name tag, prepended by af_
\set myschema af_:tag
-- to use in identifier in query.  without double quote it is converted to lower case
\set ident_myschema '\"' :myschema '\"'
-- to use as literal string
\set quote_myschema '\'' :myschema '\''

-- set search path
SET search_path TO :ident_myschema , public;
SHOW search_path;

-- list tables
\dt

-- count rows of each table

DROP FUNCTION IF EXISTS public.count_rows(text);
CREATE OR REPLACE FUNCTION public.count_rows(tbl text, OUT result bigint) 
AS
$$
BEGIN
execute format( 'SELECT count(*) FROM %s;' , quote_ident(tbl))
--execute 'SELECT count(*) FROM af_in_1;'
into result;
END
$$ 
language plpgsql volatile;

--SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname = :quote_myschema;
WITH tables AS (
	SELECT schemaname, tablename 
	FROM pg_catalog.pg_tables 
	WHERE schemaname = :quote_myschema
)
SELECT schemaname, tablename, count_rows(tablename) row_count FROM tables;
