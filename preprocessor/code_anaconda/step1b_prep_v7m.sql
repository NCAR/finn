-- schema name tag, prepended by af_
\set myschema af_:tag
-- to use in identifier in query.  without double quote it is converted to lower case
\set ident_myschema '\"' :myschema '\"'
-- to use as literal string
\set quote_myschema '\'' :myschema '\''

SET search_path TO :ident_myschema , public;
SHOW search_path;

-- filter persistanct source or not
\set my_filter_persistent_sources :filter_persistent_sources

-- first/last date (in local time) to retain.  pass string of YYYY-MM-DD, or N
\set my_date_range '\'':date_range'\''

-- definition of date, approximate local solar time (LST) or coordinated universal time (UTC)
\set my_date_definition '\'':date_definition'\''
\set

\set ON_ERROR_STOP on

DO language plpgsql $$ begin
	RAISE NOTICE 'tool: start, %', clock_timestamp();
END $$;

DO language plpgsql $$ begin
	RAISE NOTICE 'tool: here, %', clock_timestamp();
END $$;
-- -------------------------------
-- -- Part 1: Setting up tables --
-- -------------------------------
-- 
-- -- make working table
-- DROP TABLE IF EXISTS work_pnt;
-- CREATE TABLE work_pnt (
-- 	rawid integer,
-- 	fireid integer,
-- 	ndetect integer,
-- 	polyid integer,
-- 	geom_pnt geometry,
-- 	lon double precision,
-- 	lat double precision,
-- 	scan double precision,
-- 	track double precision,
-- 	acq_date_utc date,
-- 	acq_time_utc character(4),
-- 	acq_date_lst date,
-- 	acq_datetime_lst timestamp without time zone,
-- 	acq_date_use date,
-- 	instrument character(5),
-- 	confident boolean,
-- 	anomtype integer, -- "Type" field of AF product, 0-3
-- 	frp double precision,
-- 	alg_agg integer, -- algorithm to be used for aggregation, 1 for aggressive, 2 for conservative
-- 	fireid1 integer, -- fireid based on aggressive algorithm
-- 	fireid2 integer, -- fireid based on conservative algorithm
-- 	ndetect1 integer,
-- 	ndetect2 integer,
-- 	geom_sml geometry
-- 	);
-- 
-- DO language plpgsql $$ begin
-- 	RAISE NOTICE 'tool: here, %', clock_timestamp();
-- END $$;
-- 
-- -- group pixels, and lone detections in one table of fire polygons
-- drop table if exists work_lrg1;
-- create table work_lrg1 (
-- 	fireid integer primary key not null,
-- 	geom_lrg geometry,
-- 	acq_date_use date,
-- 	ndetect integer,
-- 	area_sqkm double precision,
-- 	alg_agg integer
-- 	);
-- 

-- similar to above but definition of nearby detection is conservative
drop table if exists work_lrg2;
create table work_lrg2 (
	fireid integer primary key not null,
	geom_lrg geometry(polygon, 4326),
	acq_date_use date,
	ndetect integer,
	area_sqkm double precision,
	alg_agg integer
	);
-- combined
drop table if exists work_lrg;
create table work_lrg (
	fireid integer primary key not null,
	geom_lrg geometry(polygon, 4326),
	acq_date_use date,
	ndetect integer,
	area_sqkm double precision,
	alg_agg integer
	);

drop table if exists work_div;
create table work_div (
	polyid serial primary key ,
	fireid integer,
	cleanids integer[],
	geom geometry,
	acq_date_use date,
	area_sqkm double precision,
	alg_agg integer
	);

