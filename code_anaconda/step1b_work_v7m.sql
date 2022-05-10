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
drop table if exists work_div_oned;
create temporary table work_pnt_oned (like work_pnt excluding constraints);
create temporary table work_lrg_oned (like work_lrg2 excluding constraints);
create temporary table work_div_oned (like work_div excluding constraints);
--alter table work_div_oned drop column polyid;
-- convenient to have a temporaly serial id for work_div
CREATE TEMPORARY SEQUENCE tmp_div_seq OWNED BY work_div_oned.polyid;
ALTER TABLE work_div_oned ALTER COLUMN polyid SET DEFAULT nextval('tmp_div_seq');
ALTER TABLE work_div_oned ALTER COLUMN polyid SET NOT NULL;

-- select rawid, geom_pnt, lon, lat, scan, track, acq_date_use, confidence, cleanid work_pnt from work_pnt   where acq_date_use = :oned::date limit 1;

insert into work_pnt_oned 
(rawid, geom_pnt, lon, lat, scan, track, acq_date_use, confident, instrument, cleanid, alg_agg, fireid1, ndetect1)
select rawid, geom_pnt, lon, lat, scan, track, acq_date_use, confident, instrument, cleanid , alg_agg, fireid1, ndetect1
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
add column pix_dy double precision,
add column geom_pix geometry
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
pix_dx = .5 * fire_size  * 360. / consts.great_circle / cos( lat / 180. * pi()),
pix_dy = .5 * fire_size * 360. / consts.great_circle 
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
fireid2 = g.fireid,
ndetect2 = g.ndetect
from tbl_togrp g
where p.cleanid = g.lhs;


do language plpgsql $$ begin
raise notice 'tool: step2.2c (upd tbl_pnt lhs) done, %', clock_timestamp();
end $$;

update work_pnt_oned p set
fireid2 = g.fireid,
ndetect2 = g.ndetect
from tbl_togrp g
where p.fireid2 is null and
p.cleanid = g.rhs;


do language plpgsql $$ begin
raise notice 'tool: step2.2d (upd tbl_pnt rhs) done, %', clock_timestamp();
end $$;


-- complete the fireid column of the pnt table
-- records which are not inluded in tbl_adj_det are lone detection
-- cleanid becomes fireid in such case, and ndetect is 1
update work_pnt_oned set
fireid2 = cleanid,
ndetect2 = 1
where acq_date_use = :oned::date 
and fireid2 is null;


do language plpgsql $$ begin
raise notice 'tool: step2.2e (upd tbl_pnt lone) done, %', clock_timestamp();
end $$;

-- copy over attributes to work_pnt
update work_pnt t set
fireid2 = p.fireid2,
ndetect2 = p.ndetect2,
geom_sml = p.geom_sml
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
select fireid2, geom_sml from work_pnt_oned
where ndetect2 = 1;

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
ndetect = p.ndetect2
from work_pnt_oned as p
where work_lrg_oned.fireid = p.fireid2;

update work_lrg_oned set
area_sqkm = st_area(geom_lrg, true) / 1000000.;

-- export
insert into work_lrg2
select fireid, geom_lrg, acq_date_use, ndetect, area_sqkm, null::integer
from work_lrg_oned;

do language plpgsql $$ begin
raise notice 'tool: step2 done, %', clock_timestamp();
end $$;

-- combine
delete from work_lrg_oned l
using work_pnt_oned p
where l.fireid = p.fireid2 and p.alg_agg = 1;

update work_lrg_oned l set
alg_agg = p.alg_agg
from work_pnt_oned p
where l.fireid = p.fireid2 and p.alg_agg = 2;
;


insert into work_lrg_oned
select fireid, geom_lrg, acq_date_use, ndetect, area_sqkm, alg_agg
from work_lrg1 where acq_date_use = :oned::text::date and alg_agg = 1;

insert into work_lrg
select fireid, geom_lrg, acq_date_use, ndetect, area_sqkm, alg_agg
from work_lrg_oned;

update work_pnt_oned set
fireid = fireid1, 
ndetect = ndetect1
where alg_agg = 1;

update work_pnt_oned set
fireid = fireid2, 
ndetect = ndetect2
where alg_agg = 2;

update work_pnt set
fireid = fireid1, 
ndetect = ndetect1
where alg_agg = 1;

update work_pnt set
fireid = fireid2, 
ndetect = ndetect2
where alg_agg = 2;

-- debugging
insert into dbg_pnt_oned
select rawid, fireid, ndetect, polyid, geom_pnt, lon, lat, scan, track, acq_date_utc, 
	acq_time_utc,
	acq_date_lst,
	acq_datetime_lst,
	acq_date_use,
	instrument,
	confident,
	anomtype,
	frp,
	alg_agg,
	fireid1,
	fireid2,
	ndetect1,
	ndetect2,
	geom_sml
from work_pnt_oned;

insert into dbg_lrg_oned
select * 
from work_lrg_oned;


--------------------------------------------------------
-- STEP 3: generate work_div (aka subdivided polygon) --
--------------------------------------------------------
--------------------------------------------------
-- STEP 3.1: prepare tbl_close (aka near table) --
--------------------------------------------------

-- generate near table
-- invdist is inverse distance, or small distance when two points coincide
-- criteria is 30 sec, even if af is VIIRS only...  TODO is it OK?  i think so because this has more to do with raster pixel size
drop table if exists tbl_close;
create temporary table tbl_close as
select aid as lhs, bid as rhs, 
case when dist=0. then 1./(1./60./60.) else 1./dist end as invdist,
acq_date_use, fireid
from (

	select 
	a.fireid as fireid,
	a.acq_date_use as acq_date_use,
	a.cleanid as aid,
	a.geom_pnt as ageom, 
	b.cleanid as bid, 
	b.geom_pnt as bgeom,
	st_distance(a.geom_pnt, b.geom_pnt) as dist
	from work_pnt_oned as a 
	inner join work_pnt_oned as b
	on a.acq_date_use = b.acq_date_use
	and a.fireid = b.fireid
	and st_dwithin(a.geom_pnt, b.geom_pnt, .5/60.)
	--and st_dwithin(a.geom_pnt, b.geom_pnt, .375*.5/60.)
	and a.cleanid < b.cleanid
) as foo
where dist < .5/60.
--where dist < .375*.5/60.
;


do language plpgsql $$ begin
raise notice 'tool: step3.1 (tbl_close) done, %', clock_timestamp();
end $$;

------------------------------------------------------------------------------------
-- STEP 3.2: identify detections to be dropped from being seed of Voronoi polygon --
------------------------------------------------------------------------------------

drop table if exists tbl_toskim;
create temporary table tbl_toskim as
select (pnt2drop).id, (pnt2drop).others, fireid
from (
	select pnt2drop(lhs, rhs, invdist) pnt2drop, fireid
	from (
		select array_agg(lhs) lhs, array_agg(rhs) rhs, array_agg(invdist) invdist, fireid 
		from tbl_close group by fireid
	) foo
)bar ;


do language plpgsql $$ begin
raise notice 'tool: step3.2 (tbl_toskim) done, %', clock_timestamp();
end $$;


----------------------------------------------------------------------
-- STEP 3.3: identify points to be added as seed of Voronoi polygon --
----------------------------------------------------------------------

-- generate points which subsitutes multiple points whose score was tie
drop table if exists tmp_fillers;
create temporary table tmp_fillers as
select baz.id, st_centroid(st_collect(baz.geom_pnt)) as geom
from (
	select bar.id, bar.member, p.geom_pnt
	from (

		select id, unnest(memebers) member 
		from (
			select id, array_prepend(id, others) as memebers 
			from tbl_toskim
			where array_length(others,1) > 0
		) foo
	) bar
	inner join
	work_pnt_oned p
	on bar.member = p.cleanid
) baz
group by baz.id;

do language plpgsql $$ begin
raise notice 'tool: step3.3 (tmp_skmpnt) done, %', clock_timestamp();
end $$;


---------------------------------------------------------------------
-- STEP 3.4: finalize points to be used as seed of Voronoi polygon --
---------------------------------------------------------------------

-- start from work_pnt, drop pnts specified in tbl_toskim, and also substitute with mid-ponts if needed
drop table if exists tmp_skmpnt;
create temporary table tmp_skmpnt as
select p.cleanid, p.fireid, p.geom_pnt, p.acq_date_use 
from work_pnt_oned p left join tbl_toskim s
on p.cleanid = s.id
where s.id is null
union all
select -p.cleanid, p.fireid, f.geom, p.acq_date_use
from work_pnt_oned p inner join tmp_fillers f
on p.cleanid = f.id
;



do language plpgsql $$ begin
raise notice 'tool: step3.4 (tmp_skmpnt) done, %', clock_timestamp();
end $$;


---------------------------------------------------------------------
-- STEP 3.5: use Voronoi polygons to cut burned area (ndetect > 3) --
---------------------------------------------------------------------

-- use skimmed table to generate voronoi polygons
drop table if exists tmp_vorpnts;
create temporary table tmp_vorpnts as
select fireid, st_collect(geom_pnt) as geom, acq_date_use, count(fireid) as npnts from tmp_skmpnt
group by acq_date_use, fireid;

do language plpgsql $$ begin
raise notice 'tool: step3.4a (tmp_vorpnts) done, %', clock_timestamp();
end $$;

-- voronoi polygons when points are more than three
drop table if exists tmp_vorpnts_gt3;
create temporary table tmp_vorpnts_gt3 as
select fireid, geom, acq_date_use, npnts from tmp_vorpnts
where npnts > 3;


drop table if exists tmp_vor;
create temporary table tmp_vor (
	fireid integer,
	geom geometry,
	acq_date_use date
);

do language plpgsql $$
	declare
	i_fireid integer;
	rec record;
	begin
		for i_fireid in
			select t.fireid from tmp_vorpnts_gt3 as t
			loop
				with onefire as (
					select vv.fireid, vv.geom, vv.acq_date_use, vv.npnts
					from tmp_vorpnts_gt3 as vv
					where vv.fireid = i_fireid
				)
				insert into tmp_vor (fireid, geom, acq_date_use)
				--select v.fireid, st_voronoipolygons(v.geom, 0., l.geom_lrg) as geom, v.acq_date_use 
				select v.fireid, st_voronoi_py(v.geom) as geom, v.acq_date_use 
				--from tmp_vorpnts_gt3 as v 
				from onefire as v 
				--inner join work_lrg_oned as l 
				--on l.acq_date_use = v.acq_date_use and l.fireid = v.fireid
				--where v.npnts > 1;
				where v.npnts > 3;
			end loop;
			exception
			when others then
				raise notice 'tool: died with i_fireid %', i_fireid;
				for rec in select t.fireid, st_astext(t.geom) as wkt_pnt, t.acq_date_use, t.npnts
					from  tmp_vorpnts_gt3 as t 
					where t.fireid = i_fireid
					loop
						raise notice 'tool: fireid, wkt_pnt, acq_date_use, npnts % % % %', rec.fireid, rec.wkt_pnt, rec.acq_date_use, rec.npnts;
					end loop;
				raise notice 'tool: sqlerrm %', sqlerrm;
				raise notice 'tool: sqlstate %', sqlstate;
				raise '';

	end $$;

do language plpgsql $$ begin
raise notice 'tool: step3.5b (tmp_vor) done, %', clock_timestamp();
end $$;


drop table if exists tmp_vorpoly;
create temporary table tmp_vorpoly  as 
select st_makevalid((foo.dump).geom) as geom,  foo.fireid, foo.acq_date_use from (
	select st_dump(geom) as dump, fireid, acq_date_use from tmp_vor) as foo;


do language plpgsql $$ begin
raise notice 'tool: step3.5c (tmp_vorpoly) done, %', clock_timestamp();
end $$;



-- divided into >3 piecies (using voronoi polygons)
-- insert into work_div_oned (fireid, geom, acq_date_use)
-- --select l.fireid, st_setsrid(st_intersection(l.geom_lrg, v.geom), 4326) as geom,  l.acq_date_use
-- --select l.fireid, st_intersection(l.geom_lrg, st_setsrid(v.geom, 4326)) as geom,  l.acq_date_use
-- select l.fireid, st_intersection(l.geom_lrg, v.geom) as geom,  l.acq_date_use

with foo as ( 
	select l.fireid, st_intersection(l.geom_lrg, v.geom) as geom,  l.acq_date_use
	from tmp_vorpoly as v inner join work_lrg_oned as l on l.acq_date_use = v.acq_date_use and l.fireid = v.fireid) --; -- and st_intersects(v.geom, l.geom_lrg);
insert into work_div_oned (fireid, geom, acq_date_use, area_sqkm)
select fireid, geom, acq_date_use, st_area(geom, true) / 1000000. from foo;


do language plpgsql $$ begin
raise notice 'tool: step3.5d (intersect with vorpoly) done, %', clock_timestamp();
end $$;



----------------------------------------------------------------------------------------
-- STEP 3.6: use custom made polygons to cut burned area (ndetect < 3 && ndetect > 1) --
----------------------------------------------------------------------------------------

-- polygon needs two or three points, use line(s) perpendicular to edge(s)
drop table if exists tmp_cutter;
create temporary table tmp_cutter as
select fireid, st_cutter_py(geom) as geom, acq_date_use from tmp_vorpnts
where (npnts = 2 or npnts = 3);


drop table if exists tmp_cutpoly;
create temporary table tmp_cutpoly  as 
select st_makevalid((foo.dump).geom) as geom,  foo.fireid, foo.acq_date_use from (
	select st_dump(geom) as dump, fireid, acq_date_use from tmp_cutter) as foo;


do language plpgsql $$ begin
raise notice 'tool: step3.6a (tmp_cutpoly) done, %', clock_timestamp();
end $$;


-- divided into 2 or 3 piecies (using line(s) perpenducular to edges)
-- insert into work_div_oned (fireid, geom, acq_date_use)
-- select l.fireid, st_intersection(l.geom_lrg, v.geom) as geom,  l.acq_date_use
-- from tmp_cutpoly as v inner join work_lrg_oned as l on l.acq_date_use = v.acq_date_use and l.fireid = v.fireid;
with foo as ( 
	select l.fireid, st_intersection(l.geom_lrg, v.geom) as geom,  l.acq_date_use
	from tmp_cutpoly as v inner join work_lrg_oned as l on l.acq_date_use = v.acq_date_use and l.fireid = v.fireid)
insert into work_div_oned (fireid, geom, acq_date_use, area_sqkm)
select fireid, geom,  acq_date_use, st_area(geom, true) / 1000000. from foo;

do language plpgsql $$ begin
raise notice 'tool: step3.6b (split with cutter) done, %', clock_timestamp();
end $$;


-------------------------------------
-- STEP 3.7: drop funky geometries --
-------------------------------------

-- delete from work_div_oned as d
-- where st_polsbypopper(d.geom


-----------------------------------------------------
-- STEP 3.8: undivided burned areas (ndetect == 1) --
-----------------------------------------------------

-- undivided
-- insert into work_div_oned (fireid, geom, acq_date_use)
-- select l.fireid, st_setsrid(l.geom_lrg, 4326) as geom, l.acq_date_use
-- from tmp_vorpnts as v inner join work_lrg_oned as l on l.acq_date_use = v.acq_date_use and l.fireid = v.fireid
-- where v.npnts = 1;
-- --where v.npnts <= 3;
with foo as ( 
	select l.fireid, st_setsrid(l.geom_lrg, 4326) as geom, l.acq_date_use 
	from tmp_vorpnts as v inner join work_lrg_oned as l on l.acq_date_use = v.acq_date_use and l.fireid = v.fireid 
	where v.npnts = 1 
	--where v.npnts <= 3
)
insert into work_div_oned (fireid, geom, acq_date_use, area_sqkm)
select fireid, geom, acq_date_use, st_area(geom, true) / 1000000. from foo;



do language plpgsql $$ begin
raise notice 'tool: step3.8 (lone detections) done, %', clock_timestamp();
end $$;

-----------------------------------------------------
-- STEP 3.9: list of points in subdivided polygons --
-----------------------------------------------------

-- TODO see how costly this is, and make this to be option if it is
CREATE INDEX work_div_gix ON work_div_oned USING gist( geom );

WITH foo AS (
	SELECT p.cleanid, d.polyid 
	FROM work_pnt_oned AS p INNER JOIN work_div_oned AS d 
	ON d.geom && p.geom_pnt
	AND ST_Within( p.geom_pnt, d.geom )
), bar AS (
	SELECT polyid, array_agg(cleanid) cleanids
	FROM foo
	GROUP BY polyid
)
UPDATE work_div_oned SET cleanids = bar.cleanids
FROM bar
WHERE work_div_oned.polyid = bar.polyid;

do language plpgsql $$ begin
raise notice 'tool: step3.9 (points in polygon) done, %', clock_timestamp();
end $$;

--------------------------------------------------------------
--- STEP 3.10 (experimental) update work_pnt here for polyid --
--------------------------------------------------------------
-- TODO this could be costly too..
WITH foo AS (
	SELECT polyid, unnest(cleanids) cleanid
	FROM work_div_oned
)
UPDATE work_pnt p SET
polyid = foo.polyid
FROM foo
WHERE p.cleanid = foo.cleanid;
do language plpgsql $$ begin
raise notice 'tool: step3.10 (points in polygon work_pnt) done, %', clock_timestamp();
end $$;


---------------------
-- STEP 3.11: push --
---------------------

-- push
insert into work_div(fireid, cleanids, geom, acq_date_use, area_sqkm)
select fireid, cleanids, geom, acq_date_use, area_sqkm from work_div_oned;


do language plpgsql $$ begin
raise notice 'tool: step3 done, %', clock_timestamp();
end $$;

--select :oned;
-- remember which date being processed for log purpose
drop table if exists tmp_oned;
create temporary table tmp_oned (
	oned text
);
insert into tmp_oned
(oned) values (:oned);


-- just put changes posteriori to the log
-- time duration becoms meaningless...
DO LANGUAGE plpgsql $$
  DECLARE
    i bigint;
  BEGIN
    i := log_checkin('agg to large', 'work_lrg_oned', (select count(*) from work_pnt_oned), (select oned from tmp_oned));
    i := log_checkout(i, (select count(*) from work_lrg_oned) );
    i := log_checkin('subdiv', 'work_div_oned', (select count(*) from work_lrg_oned), (select  oned from tmp_oned));
    i := log_checkout(i, (select count(*) from work_div_oned) );
  END
$$;

