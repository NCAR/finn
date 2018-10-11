set search_path to global_2016,public;

do language plpgsql $$ begin
	raise notice 'tool: start, %', clock_timestamp();
end $$;


-- grab one day data
-- actually better do this as cte, worried about name contention
drop table if exists work_div_oned;
-- create table work_div_oned (
-- 	polyid integer,
-- 	polyid_orig integer,
-- 	fireid integer,
-- 	geom geometry,
-- 	acq_date date,
-- 	area_sqkm double precision
-- 	);


drop table if exists tmp_int_vcf;
create table tmp_int_vcf (
polyid integer,
val_tree double precision,
val_herb double precision,
val_bare double precision,
acq_date date);



drop table if exists tmp_int_lct;
create table tmp_int_lct (
	polyid integer,
	val_lct integer,
	afrac double precision,
	acq_date date);

drop table if exists out_div;
create table  out_div (
	polyid integer,
	fireid integer,
	geom geometry,
	cen_lon double precision,
	cen_lat double precision,
	acq_date date,
	area_sqkm double precision,
	lct integer,
	flct double precision,
	tree double precision,
	herb double precision,
	bare double precision
);


-- function to work around bug in st_clip (fails when polygon barely intersects with raster)
-- not sure how much damage this has on performance
create or replace function st_clip_fuzzy( 
	rast raster, nband integer[],
	geom geometry,
	nodataval double precision[] DEFAULT NULL, crop boolean DEFAULT TRUE
)
	returns raster
	as $$
	declare 
	rec record;
	g geometry;
	begin
		return st_clip($1, $2, $3, $4, $5);
	exception
	when others then
		select st_intersection(st_envelope(rast), geom) into g;
		raise warning 'st_clip_fuzzy: intersection %', st_astext(g);
		raise warning 'st_clip_fuzzy: area intersection %', st_area(g);
		raise warning 'st_clip_fuzzy: area pixel %', abs(ST_ScaleX(rast) * ST_ScaleY(rast));
		raise warning 'st_clip_fuzzy: area ratio %', st_area(g) / abs(ST_ScaleX(rast) * ST_ScaleY(rast));
		
		return ST_MakeEmptyRaster(0, 0, ST_UpperLeftX(rast), ST_UpperLeftY(rast), ST_ScaleX(rast), ST_ScaleY(rast), ST_SkewX(rast), ST_SkewY(rast), ST_SRID(rast));
	end;
	$$ language 'plpgsql' immutable;

CREATE OR REPLACE FUNCTION st_clip_fuzzy(
	rast raster, nband integer,
	geom geometry,
	nodataval double precision, crop boolean DEFAULT TRUE
)
	RETURNS raster AS
	$$ SELECT ST_Clip_fuzzy($1, ARRAY[$2]::integer[], $3, ARRAY[$4]::double precision[], $5) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION st_clip_fuzzy(
	rast raster, nband integer,
	geom geometry,
	crop boolean
)
	RETURNS raster AS
	$$ SELECT ST_Clip_fuzzy($1, ARRAY[$2]::integer[], $3, null::double precision[], $4) $$
	LANGUAGE 'sql' IMMUTABLE ;

CREATE OR REPLACE FUNCTION st_clip_fuzzy(
	rast raster,
	geom geometry,
	nodataval double precision[] DEFAULT NULL, crop boolean DEFAULT TRUE
)
	RETURNS raster AS
	$$ SELECT ST_Clip_fuzzy($1, NULL, $2, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION st_clip_fuzzy(
	rast raster,
	geom geometry,
	nodataval double precision, crop boolean DEFAULT TRUE
)
	RETURNS raster AS
	$$ SELECT ST_Clip_fuzzy($1, NULL, $2, ARRAY[$3]::double precision[], $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION st_clip_fuzzy(
	rast raster,
	geom geometry,
	crop boolean
)
	RETURNS raster AS
	$$ SELECT ST_Clip_fuzzy($1, NULL, $2, null::double precision[], $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
