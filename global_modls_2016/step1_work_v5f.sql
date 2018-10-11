SET search_path TO global_2016,public;

\set ON_ERROR_STOP on

do language plpgsql $$ begin
	raise notice 'tool: start, %', clock_timestamp();
end $$;


-- pick only one day data
drop table if exists work_pnt_oned;
drop table if exists work_lrg_oned;
drop table if exists work_div_oned;
create temporary table work_pnt_oned (like work_pnt excluding constraints);
create temporary table work_lrg_oned (like work_lrg excluding constraints);
create temporary table work_div_oned (like work_div excluding constraints);
alter table work_div_oned drop column polyid;

-- select rawid, geom_pnt, lon, lat, scan, track, acq_date, confidence, cleanid work_pnt from work_pnt   where acq_date = :oned::date limit 1;

insert into work_pnt_oned 
(rawid, geom_pnt, lon, lat, scan, track, acq_date, confidence, cleanid)
select rawid, geom_pnt, lon, lat, scan, track, acq_date, confidence, cleanid 
from work_pnt where acq_date = :oned::date;

do language plpgsql $$
	declare
	cur cursor for select acq_date from work_pnt_oned limit 1;
	rec record;
	begin
	raise notice 'tool: oneday done, %', clock_timestamp();
	open cur;
	fetch cur into rec;
	raise notice 'tool: oned is, %', rec.acq_date;
end $$;



-- calculate dx, dy (half of the sides of rectangles)_
alter table work_pnt_oned
add column fire_dx double precision, 
add column fire_dy double precision,
add column pix_dx double precision, 
add column pix_dy double precision,
add column geom_pix geometry
;

-- !!! hard wired pixfac!!!
with consts as ( select 
	2. * pi() * 6370.997 as great_circle,
	1. as fire_size,
	1.1 as pixfac
	 ) 
update work_pnt_oned
set 
fire_dx = .5 * consts.fire_size  * 360. / consts.great_circle / cos( lat / 180. * pi()),
fire_dy = .5 * consts.fire_size * 360. / consts.great_circle ,
pix_dx = pixfac * .5 * work_pnt_oned.scan * 360. / consts.great_circle / cos( lat / 180. * pi()),
pix_dy = pixfac * .5 * work_pnt_oned.track * 360. / consts.great_circle 
from consts;

-- generate fire polygons (small)
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

create index work_pix_gix on work_pnt_oned using gist( geom_pix );
do language plpgsql $$ begin
raise notice 'tool: step1 gist done, %', clock_timestamp();
end $$;

-- generate near table
drop table if exists tbl_adj_det;
create temporary table tbl_adj_det as
select aid as lhs, bid as rhs, st_convexhull(st_collect(ageom, bgeom)) as geom_pair, acq_date, null::integer as fireid
from (

	select 
	a.cleanid as aid,
	a.acq_date acq_date,
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
on a.acq_date = b.acq_date
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





-- identify pixels to be grouped
drop table if exists tbl_togrp;
create temporary table tbl_togrp as
select (pnt2grp).fireid, (pnt2grp).lhs, (pnt2grp).rhs, (pnt2grp).ndetect
from (
	select pnt2grp(lhs, rhs) pnt2grp
	from (
		select array_agg(lhs) lhs, array_agg(rhs) rhs
		from tbl_adj_det group by acq_date  -- TODO add more grouping, like spatial, if i do
	) foo
) bar;

do language plpgsql $$ begin
raise notice 'tool: step2.2a (tbl_togrp) done, %', clock_timestamp();
end $$;
-- TODO index?

update tbl_adj_det a set
fireid = g.fireid
from tbl_togrp g
where a.lhs = g.lhs and a.rhs = g.rhs;

do language plpgsql $$ begin
raise notice 'tool: step2.2b (upd tbl_adj_det) done, %', clock_timestamp();
end $$;

update work_pnt_oned p set
fireid = g.fireid,
ndetect = g.ndetect
from tbl_togrp g
where p.cleanid = g.lhs;


do language plpgsql $$ begin
raise notice 'tool: step2.2c (upd tbl_pnt lhs) done, %', clock_timestamp();
end $$;

update work_pnt_oned p set
fireid = g.fireid,
ndetect = g.ndetect
from tbl_togrp g
where p.fireid is null and
p.cleanid = g.rhs;


do language plpgsql $$ begin
raise notice 'tool: step2.2d (upd tbl_pnt rhs) done, %', clock_timestamp();
end $$;


-- complete the fireid column of the pnt table
update work_pnt_oned set
fireid = cleanid,
ndetect = 1
where acq_date = :oned::date 
and fireid is null;


do language plpgsql $$ begin
raise notice 'tool: step2.2e (upd tbl_pnt lone) done, %', clock_timestamp();
end $$;

-- copy over attributes
update work_pnt t set
fireid = p.fireid,
ndetect = p.ndetect,
geom_sml = p.geom_sml
from work_pnt_oned p
where t.cleanid = p.cleanid;



do language plpgsql $$ begin
raise notice 'tool: step2.2 (fireid) done, %', clock_timestamp();
end $$;

insert into work_lrg_oned(fireid, geom_lrg)
select fireid, st_union(geom_pair) from tbl_adj_det group by fireid;

do language plpgsql $$ begin
raise notice 'tool: step2.3b (insert grp) done, %', clock_timestamp();
end $$;

insert into work_lrg_oned(fireid, geom_lrg)
select fireid, geom_sml from work_pnt_oned
where ndetect = 1;

do language plpgsql $$ begin
raise notice 'tool: step2.3c (insert solo) done, %', clock_timestamp();
end $$;


do language plpgsql $$ begin
raise notice 'tool: step2.3 (work_lrg w hole) done, %', clock_timestamp();
end $$;


--make table of holes to be kept
--!!! hard-wired threshold for filling small sized hole!!!  15sec * 15sec!

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
	and st_area(geom) > 1/240./240. 
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


-- get necessary attributes for fire polygons
update work_lrg_oned set
acq_date = p.acq_date,
ndetect = p.ndetect
from work_pnt_oned as p
where work_lrg_oned.fireid = p.fireid;

update work_lrg_oned set
area_sqkm = st_area(st_setsrid(geom_lrg, 4236)::geography) / 1000000.;

-- export
insert into work_lrg
select fireid, geom_lrg, acq_date, ndetect, area_sqkm
from work_lrg_oned;

do language plpgsql $$ begin
raise notice 'tool: step2 done, %', clock_timestamp();
end $$;




-- generate near table
-- invdist is inverse distance, or small distance when two points coincide
drop table if exists tbl_close;
create temporary table tbl_close as
select aid as lhs, bid as rhs, 
case when dist=0. then 1./(1./60./60.) else 1./dist end as invdist,
acq_date, fireid
from (

	select 
	a.fireid as fireid,
	a.acq_date as acq_date,
	a.cleanid as aid,
	a.geom_pnt as ageom, 
	b.cleanid as bid, 
	b.geom_pnt as bgeom,
	st_distance(a.geom_pnt, b.geom_pnt) as dist
	from work_pnt_oned as a 
	inner join work_pnt_oned as b
	on a.acq_date = b.acq_date
	and a.fireid = b.fireid
	and st_dwithin(a.geom_pnt, b.geom_pnt, .5/60.)
	and a.cleanid < b.cleanid
) as foo
where dist < .5/60.
;


do language plpgsql $$ begin
raise notice 'tool: step3.1 (tbl_close) done, %', clock_timestamp();
end $$;


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


-- start from work_pnt, drop pnts specified in tbl_toskim, and also substitute with mid-ponts if needed
drop table if exists tmp_skmpnt;
create temporary table tmp_skmpnt as
select p.cleanid, p.fireid, p.geom_pnt, p.acq_date 
from work_pnt_oned p left join tbl_toskim s
on p.cleanid = s.id
where s.id is null
union all
select -p.cleanid, p.fireid, f.geom, p.acq_date
from work_pnt_oned p inner join tmp_fillers f
on p.cleanid = f.id
;



do language plpgsql $$ begin
raise notice 'tool: step3.3 (tmp_skmpnt) done, %', clock_timestamp();
end $$;



-- use skimmed table to generate voronoi polygons
drop table if exists tmp_vorpnts;
create temporary table tmp_vorpnts as
select fireid, st_collect(geom_pnt) as geom, acq_date, count(fireid) as npnts from tmp_skmpnt
group by acq_date, fireid;

do language plpgsql $$ begin
raise notice 'tool: step3.4a (tmp_vorpnts) done, %', clock_timestamp();
end $$;

-- voronoi polygons when points are more than one
drop table if exists tmp_vorpnts_gt3;
create temporary table tmp_vorpnts_gt3 as
select fireid, geom, acq_date, npnts from tmp_vorpnts
where npnts > 3;


drop table if exists tmp_vor;
create temporary table tmp_vor (
	fireid integer,
	geom geometry,
	acq_date date
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
					select vv.fireid, vv.geom, vv.acq_date, vv.npnts
					from tmp_vorpnts_gt3 as vv
					where vv.fireid = i_fireid
				)
insert into tmp_vor (fireid, geom, acq_date)
--select v.fireid, st_voronoipolygons(v.geom, 0., l.geom_lrg) as geom, v.acq_date 
select v.fireid, st_voronoi_py(v.geom) as geom, v.acq_date 
--from tmp_vorpnts_gt3 as v 
from onefire as v 
--inner join work_lrg_oned as l 
--on l.acq_date = v.acq_date and l.fireid = v.fireid
--where v.npnts > 1;
where v.npnts > 3;
			end loop;
			exception
			when others then
				raise notice 'tool: died with i_fireid %', i_fireid;
				for rec in select t.fireid, st_astext(t.geom) as wkt_pnt, t.acq_date, t.npnts
					from  tmp_vorpnts_gt3 as t 
					where t.fireid = i_fireid
					loop
						raise notice 'tool: fireid, wkt_pnt, acq_date, npnts % % % %', rec.fireid, rec.wkt_pnt, rec.acq_date, rec.npnts;
					end loop;
				raise notice 'tool: sqlerrm %', sqlerrm;
				raise notice 'tool: sqlstate %', sqlstate;
				raise '';

	end $$;

do language plpgsql $$ begin
raise notice 'tool: step3.4b (tmp_vor) done, %', clock_timestamp();
end $$;


drop table if exists tmp_vorpoly;
create temporary table tmp_vorpoly  as 
select st_makevalid((foo.dump).geom) as geom,  foo.fireid, foo.acq_date from (
	select st_dump(geom) as dump, fireid, acq_date from tmp_vor) as foo;


do language plpgsql $$ begin
raise notice 'tool: step3.4c (tmp_vorpoly) done, %', clock_timestamp();
end $$;



-- divided into >3 piecies (using voronoi polygons)
insert into work_div_oned (fireid, geom, acq_date)
--select l.fireid, st_setsrid(st_intersection(l.geom_lrg, v.geom), 4326) as geom,  l.acq_date
--select l.fireid, st_intersection(l.geom_lrg, st_setsrid(v.geom, 4326)) as geom,  l.acq_date
select l.fireid, st_intersection(l.geom_lrg, v.geom) as geom,  l.acq_date
from tmp_vorpoly as v inner join work_lrg_oned as l on l.acq_date = v.acq_date and l.fireid = v.fireid; -- and st_intersects(v.geom, l.geom_lrg);

do language plpgsql $$ begin
raise notice 'tool: step3.4d (intersect with vorpoly) done, %', clock_timestamp();
end $$;


-- polygon needs two or three points, use line(s) perpendicular to edge(s)
drop table if exists tmp_cutter;
create temporary table tmp_cutter as
select fireid, st_cutter_py(geom) as geom, acq_date from tmp_vorpnts
where (npnts = 2 or npnts = 3);


drop table if exists tmp_cutpoly;
create temporary table tmp_cutpoly  as 
select st_makevalid((foo.dump).geom) as geom,  foo.fireid, foo.acq_date from (
	select st_dump(geom) as dump, fireid, acq_date from tmp_cutter) as foo;


do language plpgsql $$ begin
raise notice 'tool: step3.5a (tmp_cutpoly) done, %', clock_timestamp();
end $$;


-- divided into 2 or 3 piecies (using line(s) perpenducular to edges)
insert into work_div_oned (fireid, geom, acq_date)
select l.fireid, st_intersection(l.geom_lrg, v.geom) as geom,  l.acq_date
from tmp_cutpoly as v inner join work_lrg_oned as l on l.acq_date = v.acq_date and l.fireid = v.fireid;

do language plpgsql $$ begin
raise notice 'tool: step3.5b (split with cutter) done, %', clock_timestamp();
end $$;



-- undivided
insert into work_div_oned (fireid, geom, acq_date)
select l.fireid, st_setsrid(l.geom_lrg, 4326) as geom, l.acq_date
from tmp_vorpnts as v inner join work_lrg_oned as l on l.acq_date = v.acq_date and l.fireid = v.fireid
where v.npnts = 1;
--where v.npnts <= 3;

do language plpgsql $$ begin
raise notice 'tool: step3.6 (lone detections) done, %', clock_timestamp();
end $$;


update work_div_oned set
area_sqkm = st_area(geom::geography) / 1000000.;

-- push
insert into work_div(fireid, geom, acq_date, area_sqkm)
select fireid, geom, acq_date, area_sqkm from work_div_oned;


do language plpgsql $$ begin
raise notice 'tool: step3 done, %', clock_timestamp();
end $$;

