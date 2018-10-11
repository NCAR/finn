set search_path to global_2016,raster_6sec,public;
-- i tried hard to come up with ways to pass table name in the query.
-- issue is that plpgsql reads only literal string (from $$ to $$, i guess), and
-- make the content dynamic is ugly.  can be done for simple case, but i am not sure
-- its worth doing it to just change name of table in the middle
-- probably better create this entire query by shell or python that may make sense
-- also plpgsql doesnt have table name as variable, not sure i can use := or somthing to set table name
--
-- so, this \set psql variable mechanism is not working
-- intead, you have to hard wire table name lct_xxx vcf_xxx (two places) 
-- for different years
-- last year with vcf is 2015
\set vcf_yr 2016
-- last year with lct is 2013
\set lct_yr 2016

-- v3h
-- st_clip_fuzzy may have problem of ignoring intersection, but
-- since it doesnt occur often and i dont have any better logic, i will just use it
-- worst case would be the for the polygon there is no intersecting raster, 
-- resunting in empty field for lct/vcf.  in that case i guess we can fall back to some default


do language plpgsql $$ begin
	raise notice 'tool: start, %', clock_timestamp();
end $$;


-- pick only one day data
drop table if exists work_div_oned;
create temporary table work_div_oned (
 	polyid integer,
 	fireid integer,
 	geom geometry,
 	acq_date date,
 	area_sqkm double precision
 	);

insert into work_div_oned (polyid, fireid, geom, acq_date, area_sqkm)
select polyid, fireid, geom, acq_date, area_sqkm
from work_div where acq_date = :oned::date;
do language plpgsql $$
	declare
	cur cursor for select acq_date from work_div_oned limit 1;
	rec record;
	begin
	raise notice 'tool: oneday done, %', clock_timestamp();
	open cur;
	fetch cur into rec;
	raise notice 'tool: oned is, %', rec.acq_date;
end $$;

set client_min_messages to warning;
--do language plpgsql $$
	-- once in a very long while, st_clip throws error
	-- this happens when polygon barely intersects with raster
        -- i created ticket 3730 https://trac.osgeo.org/postgis/ticket/3730#ticket
        -- to work around it, i came up with visiting polygons one by one,
        -- and have begin/exception/end block to let the error to beg ignored 
        -- so this polygon got dropped.
	

--	declare
--	i_polyid integer;
--	rec record;
--	begin
--		for i_polyid in select t.polyid from work_div_oned as t 
--			loop 
--				begin 
--					with onepoly as ( 
--						select dd.polyid
--						,dd.geom
--						,dd.acq_date
--						from work_div_oned as dd
--						where dd.polyid = i_polyid
--					),
					with
					piece as (
						-- prepare polygon sections
						select d.polyid,
						-- following may fail by two or more rasons, 
						--  (1) multiband vs touching polygon (ticket 3725),
						--  (2) barely intersecting polygon (ticket 3730) 
						--  (3) something else?
						-- am going to run and let it fail, but record the polyid on failure
						st_clip_fuzzy(r.rast, d.geom) as rast, 
						d.acq_date
						-- assuming vcf raster table name tp be "vcf_global_2012", for example
						from vcf_global_:vcf_yr as r
						--from vcf_global_2014 as r
						inner join
						work_div_oned as d
						--onepoly as d
						on st_intersects(r.rast, d.geom)
					) 
					insert into tmp_int_vcf (polyid, val_tree, val_herb, val_bare, acq_date) 
					select 
					polyid, 
					(stats1).mean as val_tree, 
					(stats2).mean as val_herb, 
					(stats3).mean as val_bare, 
					acq_date
					from (
						-- calculate raster stats
						select p.polyid,
						st_summarystatsagg(p.rast, 1, true) as stats1,
						st_summarystatsagg(p.rast, 2, true) as stats2,
						st_summarystatsagg(p.rast, 3, true) as stats3,
						p.acq_date
						from piece as p
						group by p.polyid, p.acq_date
					) foo 
					; 
--				exception
--				when others then
--					insert into logs_step2_oned
--					(polyid, acq_date, rastname, origclip) 
--					select polyid, acq_date, 'lct', 1
--					from work_div_oned
--					where work_div_oned.polyid = i_polyid;
--				end;
--			end loop; 
--		end $$;



set client_min_messages to notice;


do language plpgsql $$ begin
raise notice 'tool: vcf done, %', clock_timestamp();
end $$;


set client_min_messages to warning;
--do language plpgsql $$
--	declare
--	i_polyid integer;
--	begin
--		for i_polyid in select t.polyid from work_div_oned as t 
--			loop 
--				begin 

--					with onepoly as ( 
--						select dd.polyid
--						,dd.geom
--						,dd.acq_date
--						from work_div_oned as dd
--						where dd.polyid = i_polyid
--					),
with
piece as (
       	select d.polyid,
	st_clip_fuzzy(r.rast, d.geom) as clp,
	d.acq_date
	-- assuming lct raster table name tp be "lct_global_2013", for example
	from lct_global_:lct_yr as r
--	from lct_global_2013 as r
	inner join
	work_div_oned as d
	--onepoly as d
	on st_intersects(r.rast, d.geom)
)
insert into tmp_int_lct (polyid, val_lct, afrac, acq_date)
select polyid, 
val, 
(cnt::float)/(tcnt::float) as afrac, 
acq_date from
(
	select 
	polyid, 
	(pvc).value as val,
	(pvc).count as cnt,
	tcnt,
	acq_date ,
	row_number() over (partition by polyid order by (pvc).count desc) as rnk
	from (
		-- count pixels grouped by raster value
		select polyid,
		st_valuecount(clp) as pvc,
		st_count(clp) as tcnt,
		acq_date
		from (
			select polyid,
			st_union(clp) as clp,
			acq_date
			from piece
			group by acq_date, polyid
		) bar 
	) baz
) quz where rnk = 1;
--				exception
--				when others then
--					raise warning 'tool: died with i_polyd %', i_polyid;
--					raise warning 'tool: sqlerrm %', sqlerrm;
--					raise warning 'tool: sqlstate %', sqlstate;
--					--raise ''; 
--				end;
--			end loop; 
--		end $$;
set client_min_messages to notice;

do language plpgsql $$ begin
raise notice 'tool: lct done, %', clock_timestamp();
end $$;


-- pulling all together for export
insert into out_div (polyid, fireid, geom, cen_lon, cen_lat, acq_date, area_sqkm, lct, flct, tree, herb, bare)
select d.polyid, d.fireid, d.geom, st_x(d.centroid) cen_lon, st_y(d.centroid) cen_lat, d.acq_date, d.area_sqkm, l.val_lct lct, l.afrac flct, v.val_tree tree, v.val_herb herb, v.val_bare bare
from (
select polyid, fireid, geom, acq_date, area_sqkm, st_centroid(geom) centroid from work_div_oned
) d
left join tmp_int_lct l on d.polyid = l.polyid
left join tmp_int_vcf v on d.polyid = v.polyid
;

do language plpgsql $$ begin
raise notice 'tool: ready to export, %', clock_timestamp();
raise notice 'tool: command to use is';
raise notice '  ogr2ogr -f "ESRI Shapefile" global_2014.shp PG:"host=localhost dbname=finn" -sql "select * from global_2014.out_div;"';
end $$;
-- ogr2ogr -f "ESRI Shapefile" global_2014.shp PG:"host=localhost dbname=finn" -sql "select * from global_2014.out_div;"

