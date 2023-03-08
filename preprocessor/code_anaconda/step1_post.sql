-- schema name tag, prepended by af_
\set myschema af_:tag
-- to use in identifier in query.  without double quote it is converted to lower case
\set ident_myschema '\"' :myschema '\"'
-- to use as literal string
\set quote_myschema '\'' :myschema '\''

SET search_path TO :ident_myschema , public;
SHOW search_path;


\set ON_ERROR_STOP on

-- set polyid of detection points
WITH foo AS (
	SELECT polyid, unnest(cleanids) cleanid
	FROM work_div
)
UPDATE work_pnt p SET
polyid = foo.polyid
FROM foo
WHERE p.cleanid = foo.cleanid;
