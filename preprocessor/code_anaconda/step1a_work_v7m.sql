-- schema name tag, prepended by af_
\set myschema af_:tag
-- to use in identifier in query.  without double quote it is converted to lower case
\set ident_myschema '\"' :myschema '\"'
-- to use as literal string
\set quote_myschema '\'' :myschema '\''

SET search_path TO :ident_myschema,public;

\set ON_ERROR_STOP on

do language plpgsql $$ begin
	raise notice 'tool: start, %', clock_timestamp();
end $$;

------------------------------
-- STEP 1: prepare work_pnt --
------------------------------

-- pick only one day data
drop table if exists work_pnt_oned;
drop table if exists work_lrg_oned;
-- drop table if exists work_div_oned;
create temporary table work_pnt_oned (like work_pnt excluding constraints);
create temporary table work_lrg_oned (like work_lrg1 excluding constraints);
-- create temporary table work_div_oned (like work_div excluding constraints);
--alter table work_div_oned drop column polyid;
-- convenient to have a temporaly serial id for work_div
-- CREATE TEMPORARY SEQUENCE tmp_div_seq OWNED BY work_div_oned.polyid;
-- ALTER TABLE work_div_oned ALTER COLUMN polyid SET DEFAULT nextval('tmp_div_seq');
-- ALTER TABLE work_div_oned ALTER COLUMN polyid SET NOT NULL;

-- select rawid, geom_pnt, lon, lat, scan, track, acq_date_use, confidence, cleanid work_pnt from work_pnt   where acq_date_use = :oned::date limit 1;

insert into work_pnt_oned 
(rawid, geom_pnt, lon, lat, scan, track, acq_date_use, confident, instrument, cleanid)
select rawid, geom_pnt, lon, lat, scan, track, acq_date_use, confident, instrument, cleanid 
from work_pnt where acq_date_use = :oned::text::date;

do language plpgsql $$
	declare
	cur cursor for select acq_date_use from work_pnt_oned limit 1;
	rec record;
	begin
	raise notice 'tool: oneday done, %', clock_timestamp();
	open cur;
	fetch cur into rec;
	raise notice 'tool: oned is, %', rec.acq_date_use;
end $$;



-- calculate dx, dy (half of the sides of rectangles)_
alter table work_pnt_oned
add column fire_size double precision, 
add column fire_dx double precision, 
add column fire_dy double precision,
add column pix_dx double precision, 
add column pix_dy double precision --,
-- add column geom_pix geometry
;


-- TODO make fire_size to be 1 for MODIS, .35 for VIIRS
-- !!! hard wired pixfac!!!
-- !!! hard fire_size !!!
update work_pnt_oned
set fire_size = case when (instrument = 'MODIS') then 1.0 when (instrument = 'VIIRS') then .375 else null::double precision end;
do language plpgsql $$ begin
assert (select count(*) from work_pnt_oned where fire_size is null) = 0, 'instrument?? fire_size??';
end $$;

with consts as ( select 
	2. * pi() * 6370.997 as great_circle,
	1.1 as pixfac
	 ) 
update work_pnt_oned
set 
fire_dx = .5 * fire_size  * 360. / consts.great_circle / cos( lat / 180. * pi()),
fire_dy = .5 * fire_size * 360. / consts.great_circle ,
pix_dx = pixfac * .5 * work_pnt_oned.scan * 360. / consts.great_circle / cos( lat / 180. * pi()),
pix_dy = pixfac * .5 * work_pnt_oned.track * 360. / consts.great_circle 
from consts;

-- generate fire polygons (small and pixel)
update work_pnt_oned
set geom_sml = st_setsrid(
	st_makepolygon(
		st_makeline(array[
			st_makepoint( lon - fire_dx, lat - fire_dy),
			st_makepoint( lon - fire_dx, lat + fire_dy),
			st_makepoint( lon + fire_dx, lat + fire_dy),
			st_makepoint( lon + fire_dx, lat - fire_dy),
			st_makepoint( lon - fire_dx, lat - fire_dy)]
		)
	), st_srid( geom_pnt ))
	,
geom_pix = st_setsrid(
	st_makepolygon( 
		st_makeline(array[
			st_makepoint( lon - pix_dx, lat - pix_dy),
			st_makepoint( lon - pix_dx, lat + pix_dy),
			st_makepoint( lon + pix_dx, lat + pix_dy),
			st_makepoint( lon + pix_dx, lat - pix_dy),
			st_makepoint( lon - pix_dx, lat - pix_dy)]
		)
	), st_srid( geom_pnt ))
		;


do language plpgsql $$ begin
raise notice 'tool: step1 add fld done, %', clock_timestamp();
end $$;

-- generate spatial index on pixels
create index work_pix_gix on work_pnt_oned using gist( geom_pix );
do language plpgsql $$ begin
raise notice 'tool: step1 gist done, %', clock_timestamp();
end $$;

---------------------------------------------------------
-- STEP 2: generate work_lrg (aka burned area polygon) --
---------------------------------------------------------

----------------------------------------------------
-- STEP 2.1: prepare tbl_adj_det (aka near table) --
----------------------------------------------------

-- generate near table
-- it has 
--   cleanid from lhs (lhs) 
--   cleanid from rhs (rhs) 
--   convex hull of the pair of small areas (geom_pair)
--   acquisition date in lst (acq_date_use)
--   fire id (start with empty) (fireid)
drop table if exists tbl_adj_det;
create temporary table tbl_adj_det as
select aid as lhs, bid as rhs, st_convexhull(st_collect(ageom, bgeom)) as geom_pair, acq_date_use, null::integer as fireid
from (
	-- join work_pnt_oned to itself, and 
        -- find pair which is within distance criteria
	select 
	a.cleanid as aid,
	a.acq_date_use acq_date_use,
	a.lon as alon,
	a.lat as alat,
	a.pix_dx as adx, 
	a.pix_dy as ady,
	a.geom_sml as ageom, 
	b.cleanid as bid, 
	b.lon as blon,
	b.lat as blat,
	b.pix_dx as bdx, 
	b.pix_dy as bdy,
	b.geom_sml as bgeom
from work_pnt_oned as a 
inner join work_pnt_oned as b
on a.acq_date_use = b.acq_date_use
and a.geom_pix && b.geom_pix   -- THIS IS IMPORTANT, uses GIST!!!
and st_dwithin(a.geom_pnt, b.geom_pnt, a.pix_dx + a.pix_dy + b.pix_dx + b.pix_dy)
and a.cleanid < b.cleanid
) as foo
where (abs(alon-blon)<(adx+bdx)) and (abs(alat-blat)<(ady+bdy))
;

create unique index idx_pair on tbl_adj_det(lhs, rhs);

do language plpgsql $$ begin
raise notice 'tool: step2.1 (tbl_adj_det) done, %', clock_timestamp();
end $$;



-------------------------------------------------
-- STEP 2.2: identify detections to be grouped --
-------------------------------------------------

-- identify pixels to be grouped
-- fireid here is smallest cleanid within a group. 
drop table if exists tbl_togrp;
create temporary table tbl_togrp as
select (pnt2grp).fireid, (pnt2grp).lhs, (pnt2grp).rhs, (pnt2grp).ndetect
from (
	select pnt2grp(lhs, rhs) pnt2grp
	from (
		select array_agg(lhs) lhs, array_agg(rhs) rhs
		from tbl_adj_det group by acq_date_use  -- TODO add more grouping, like spatial, if i do
	) foo
) bar;

do language plpgsql $$ begin
raise notice 'tool: step2.2a (tbl_togrp) done, %', clock_timestamp();
end $$;
-- TODO index?

-- copy the group id (fireid) to tbl_adj_det
update tbl_adj_det a set
fireid = g.fireid
from tbl_togrp g
where a.lhs = g.lhs and a.rhs = g.rhs;

do language plpgsql $$ begin
raise notice 'tool: step2.2b (upd tbl_adj_det) done, %', clock_timestamp();
end $$;

-- copy the group id to work_pnt
update work_pnt_oned p set
fireid1 = g.fireid,
ndetect1 = g.ndetect
from tbl_togrp g
where p.cleanid = g.lhs;


do language plpgsql $$ begin
raise notice 'tool: step2.2c (upd tbl_pnt lhs) done, %', clock_timestamp();
end $$;

update work_pnt_oned p set
fireid1 = g.fireid,
ndetect1 = g.ndetect
from tbl_togrp g
where p.fireid1 is null and
p.cleanid = g.rhs;


do language plpgsql $$ begin
raise notice 'tool: step2.2d (upd tbl_pnt rhs) done, %', clock_timestamp();
end $$;


-- complete the fireid column of the pnt table
-- records which are not inluded in tbl_adj_det are lone detection
-- cleanid becomes fireid in such case, and ndetect is 1
update work_pnt_oned set
fireid1 = cleanid,
ndetect1 = 1
where acq_date_use = :oned::date 
and fireid1 is null;


do language plpgsql $$ begin
raise notice 'tool: step2.2e (upd tbl_pnt lone) done, %', clock_timestamp();
end $$;

-- copy over attributes to work_pnt
update work_pnt t set
fireid1 = p.fireid1,
ndetect1 = p.ndetect1,
geom_sml = p.geom_sml,
geom_pix = p.geom_pix
from work_pnt_oned p
where t.cleanid = p.cleanid;



do language plpgsql $$ begin
raise notice 'tool: step2.2 (fireid) done, %', clock_timestamp();
end $$;



----------------------------------------------------------
-- STEP 2.3: create work_lrg (aka burned area polygons) --
----------------------------------------------------------

-- insert aggregated detections
insert into work_lrg_oned(fireid, geom_lrg)
select fireid, st_union(geom_pair) from tbl_adj_det group by fireid;

do language plpgsql $$ begin
raise notice 'tool: step2.3b (insert grp) done, %', clock_timestamp();
end $$;

-- insert lone detections
insert into work_lrg_oned(fireid, geom_lrg)
select fireid1, geom_sml from work_pnt_oned
where ndetect1 = 1;

do language plpgsql $$ begin
raise notice 'tool: step2.3c (insert solo) done, %', clock_timestamp();
end $$;

do language plpgsql $$ begin
raise notice 'tool: step2.3 (work_lrg w hole) done, %', clock_timestamp();
end $$;


---------------------------------------------------------------------------------
-- STEP 2.4: clean large polygons (burned area polygon) by filling small holes --
---------------------------------------------------------------------------------

-- TODO if VIIRS only, make this criteria of small hole to be smaller, 5.25 sec? (3600/5.25)
--make table of holes to be kept
--!!! hard-wired threshold for filling small sized hole!!!  15sec * 15sec!  (30 sec ~ 1km)

drop table if exists tmp_hole;
create temporary table tmp_hole as
select fireid, st_collect(geom) geom
from (
	select fireid, path, geom 
	from (
		select fireid, (gdump).path[1] as path, (gdump).geom geom 
		from (
			select fireid, st_numinteriorrings(geom_lrg), st_dumprings(geom_lrg) as gdump
			from work_lrg_oned
			where st_numinteriorrings(geom_lrg) > 0
		) foo
	) bar
	where path > 0
	and st_area(st_envelope(geom)) > 1/240./240. 
	and st_area(geom, false) > 1/240./240.   -- in map unit, i.e. degreees
) baz
group by fireid
;

-- fill all holes first
update  work_lrg_oned
set geom_lrg = st_makepolygon(st_exteriorring(geom_lrg))
where st_numinteriorrings(geom_lrg) > 0;

-- punch holes to be kept
update  work_lrg_oned l
set geom_lrg = st_difference(l.geom_lrg, h.geom)
from tmp_hole as h
where l.fireid = h.fireid;

do language plpgsql $$ begin
raise notice 'tool: step2.4 (work_lrg) done, %', clock_timestamp();
end $$;


---------------------------------------------------------------
-- STEP 2.5: large polygons (burned area polygon) attributes --
---------------------------------------------------------------

-- get necessary attributes for fire polygons
update work_lrg_oned set
acq_date_use = p.acq_date_use,
ndetect = p.ndetect1
from work_pnt_oned as p
where work_lrg_oned.fireid = p.fireid1;

update work_lrg_oned set
area_sqkm = st_area(geom_lrg, true) / 1000000.;

-- export
insert into work_lrg1
select fireid, geom_lrg, acq_date_use, ndetect, area_sqkm, null::integer
from work_lrg_oned;

do language plpgsql $$ begin
raise notice 'tool: step2 done, %', clock_timestamp();
end $$;


-- this is it for Step 1a. 
