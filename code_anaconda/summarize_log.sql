-- schema name tag, prepended by af_
\set myschema af_:tag
-- to use in identifier in query.  without double quote it is converted to lower case
\set ident_myschema '\"' :myschema '\"'
-- to use as literal string
\set quote_myschema '\'' :myschema '\''

SET search_path TO :ident_myschema , public;
SHOW search_path;

\set echo all

WITH foo AS ( 
  SELECT 
  max(log_id) log_id,
  log_event,
  sum(log_nrec_change) log_nrec_change,
  min(log_nrec_before) log_nrec_before,
  max(log_nrec_after) log_nrec_after,
  max(log_time_finish) log_time_finish
  FROM tbl_log
  GROUP BY log_event
  ORDER BY log_id
), bar AS (
  SELECT 
  (SELECT count(*) from work_pnt) n_pnt,
  (SELECT count(*) from work_lrg) n_lrg,
  (SELECT count(*) from work_div) n_div
), baz AS (

  SELECT * FROM foo
  WHERE NOT (log_event = 'agg to large' OR log_event = 'subdiv' OR log_event like 'join %')

  UNION ALL

  SELECT f.log_id, f.log_event, f.log_nrec_change, b.n_pnt, b.n_lrg, f.log_time_finish
  FROM
  (SELECT * FROM foo WHERE log_event = 'agg to large') f, bar b

  UNION ALL

  SELECT f.log_id, f.log_event, f.log_nrec_change, b.n_lrg, b.n_div, f.log_time_finish
  FROM
  (SELECT * FROM foo WHERE log_event = 'subdiv') f, bar b

  UNION ALL
  SELECT * FROM foo
  WHERE (log_event like 'join %')

)
SELECT * from baz;

-- DO LANGUAGE pgplsql $$
-- DECLARE
-- BEGIN
-- END;
-- $$;

-- vim: et sw=2


