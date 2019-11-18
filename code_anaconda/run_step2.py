import datetime
from subprocess import Popen

from run_step1 import get_first_last_day

ver = 'v8b'

def main(tag_af, rasters, firstday=None, lastday=None, run_prep=True, run_work=True):

    schema = 'af_{0}'.format( tag_af )

    # rasters is list of dicts
    # [ { 'tag': tag for the raster dataset,
    #     'kind': either 'thematic', 'continuous', 'polygons'
    #     'variables': list of variable names (optional)}
    #   } ,...]
    # when variables is omitted the raster dataset tag is going to be used to identify variable

    tag_rsts = [_['tag'] for _ in rasters]

    scrname_prep = 'step2_prep_{0}_{1}.sql'.format('_'.join(tag_rsts), ver)
    scrname_work = 'step2_work_{0}_{1}.sql'.format('_'.join(tag_rsts), ver)

    # compose commands

    #for tag_rst in tag_rsts:
    cmd_prep = 'set search_path to "{0}",public;\n'.format( schema )
    cmd_work = 'set search_path to "{0}",raster,public;\n'.format( schema )

    cmd_work += mkcmd_create_table_oned()

    tag_tbls = []
    fldnames = []
    fldtypes = []
    dctfldtbl = {}

    for rstinfo in rasters:
        # make tables
        # select mktble_thematic('lct');
        # select mktble_continuous('vcf', array['tree','herb','bare']);
        # select mktble_polygons('globreg');
        # well, it probably make more sence to compose sql comman in python....
        cmd_prep += '\n--\n-- Prepare table for {tag}\n--\n'.format(**rstinfo)
        cmd_work += '\n--\n-- Find values for {tag}\n--\n'.format(**rstinfo)
        if rstinfo['kind'] == 'thematic':
            cmd_prep += mkcmd_create_table_thematic(rstinfo['tag'], rstinfo['variable'], schema)
            cmd_work += mkcmd_insert_table_thematic(rstinfo['tag'], rstinfo['variable'], schema)
            tag_tbls += [rstinfo['tag']]
            fldnames += ['v_'+rstinfo['variable'], 'f_'+rstinfo['variable']]
            fldtypes += ['integer', 'double precision']
            dctfldtbl.update([(_ + rstinfo['variable'] , tag_tbls[-1]) for _ in ('v_','f_')])
        elif rstinfo['kind'] == 'continuous':
            cmd_prep += mkcmd_create_table_continuous(rstinfo['tag'], rstinfo['variables'], schema)
            cmd_work += mkcmd_insert_table_continuous(rstinfo['tag'], rstinfo['variables'], schema)
            tag_tbls += [rstinfo['tag']]
            fldnames += [ 'v_'+_ for _ in rstinfo['variables']]
            fldtypes += (['double precision'] * len(rstinfo['variables']))
            dctfldtbl.update([('v_'+_ , tag_tbls[-1]) for _ in rstinfo['variables']])
        elif rstinfo['kind'] == 'polygons':
            cmd_prep += mkcmd_create_table_polygons(rstinfo['tag'], rstinfo['variable'], schema)
            cmd_work += mkcmd_insert_table_polygons(rstinfo['tag'], rstinfo['variable'], rstinfo['variable_in'], schema)
            tag_tbls += [rstinfo['tag']]
            fldnames += ['v_'+rstinfo['variable']]
            fldtypes += ['integer']
            dctfldtbl.update([['v_'+rstinfo['variable'] , tag_tbls[-1]]])
        else:
            raise RuntimeError("unkown kind for raster: kind '{kind}' for raster '{tag}'".format(**rstinfo))


        #print(fldnames)
        #print(dctfldtbl)
        # TODO table for output
        cmd_prep += '\n--\n-- Prepare table for output\n--\n'
        cmd_work += '\n--\n-- Gather restuls to output\n--\n'
        cmd_prep += mkcmd_create_table_output(tag_tbls, fldnames, fldtypes, schema)
        cmd_work += mkcmd_insert_table_output(tag_tbls, fldnames, dctfldtbl, schema)

        #print(cmd_prep)
        with open(scrname_prep, 'w') as f:
            f.write(cmd_prep)
        #print(cmd_work)
        with open(scrname_work, 'w') as f:
            f.write(cmd_work)


    # run the prep script
    if run_prep:

        print("starting prep: {0}".format( datetime.datetime.now()))
        p = Popen(
                ['psql']
                + ['-f', scrname_prep]
                )
        p.communicate()

    if run_work: 

        if firstday is None or lastday is None:
            firstday, lastday = get_first_last_day(tag_af)

        dt0 = firstday
        dt1 = lastday + datetime.timedelta(days=1)

        # process each day, store output into tables
        dates = [dt0 + datetime.timedelta(days=n) for n in
                range((dt1-dt0).days)]
        for dt in dates:
            print("starting work {0}: {1}".format( dt.strftime('%Y-%m-%d'), datetime.datetime.now()))
            p = Popen(
                ['psql',] +
                ['-f', scrname_work] +
#                ['-v', ("tag=%s" % tag)] +
                ['-v', "oned='{0}'".format( dt.strftime('%Y-%m-%d'))],
                    stdout = open('out.step1.o{0}'.format( dt.strftime('%Y%m%d')),
                        'w')
                    ) 
            p.communicate()
            if p.returncode >0:
                raise RuntimeError()



    if True:
        # merge, export
        pass

# use the function to create tables
def mkcmd_create_table_thematic(tag_tbl, tag_var, schema):
    tblname = 'tbl_{0}'.format( tag_tbl )
    varname = 'v_{0}'.format( tag_var )
    frcname = 'f_{0}'.format( tag_var )
    cmd = """
drop table if exists "{schema}"."{tblname}";
create table "{schema}"."{tblname}" (
    polyid integer,
    {varname} integer,
    {frcname} double precision,
    acq_date_lst date
    );
-- clean the left over log if any
select log_purge('join {tag_tbl}');""".format(schema=schema, tblname=tblname, varname=varname, frcname=frcname, tag_tbl=tag_tbl)
    return cmd

def mkcmd_create_table_continuous(tag_tbl, tag_vars, schema):
    tblname = 'tbl_{0}'.format( tag_tbl )
    varnames = ['v_{0}'.format(_) for _ in tag_vars]
    vardefs = ['{0} double precision'.format(  _ ) for _ in varnames]
    cmd = """
drop table if exists "{schema}"."{tblname}";
create table "{schema}"."{tblname}" (
    polyid integer,
    {vardefs},
    acq_date_lst date
    );
-- clean the left over log if any
select log_purge('join {tag_tbl}'); """.format(   schema=schema, tblname=tblname, vardefs=', '.join(vardefs), tag_tbl=tag_tbl )
    return cmd

def mkcmd_create_table_polygons(tag_tbl, tag_var, schema): 
    return mkcmd_create_table_thematic(tag_tbl, tag_var, schema)

def mkcmd_create_table_output(tag_tbls, fldnames, fldtypes, schema):
    tblname = 'out_' + '_'.join(tag_tbls)
    valdefs = ['{0} {1}'.format(n, t)
            for (n, t) in zip(fldnames, fldtypes)]
    valdef = ',\n'.join(valdefs)

    cmd = """
drop table if exists "{schema}"."{tblname}";
create table "{schema}"."{tblname}" (
    polyid integer, 
    fireid integer,
    geom geometry,
    cen_lon double precision,
    cen_lat double precision,
    acq_date_lst date,
    area_sqkm double precision,
    {valdef}
    );""".format(
            schema=schema,
            tblname=tblname,
            valdef=valdef,
            )
    return cmd


def mkcmd_create_table_oned():
    cmd = """    
    do language plpgsql $$ begin
            raise notice 'tool: start, %', clock_timestamp();
    end $$;


    -- pick only one day data
    drop table if exists work_div_oned;
    create temporary table work_div_oned (
            polyid integer,
            fireid integer,
            geom geometry,
            acq_date_lst date,
            area_sqkm double precision
            );

    insert into work_div_oned (polyid, fireid, geom, acq_date_lst, area_sqkm)
    select polyid, fireid, geom, acq_date_lst, area_sqkm
    from work_div where acq_date_lst = :oned::date;
    do language plpgsql $$
            declare
            cur cursor for select acq_date_lst from work_div_oned limit 1;
            rec record;
            begin
            raise notice 'tool: oneday done, %', clock_timestamp();
            open cur;
            fetch cur into rec;
            raise notice 'tool: oned is, %', rec.acq_date_lst;
    end $$;
    """
    return cmd



def mkcmd_insert_table_thematic(tag_tbl, tag_var, schema):
    cmd = """
    set search_path to "{schema}",raster,public;

    set client_min_messages to warning;

    DO LANGUAGE plpgsql $$ 
      DECLARE
        i bigint;
      BEGIN 
        i := log_checkin('join {tag_tbl}', 'tbl_{tag_tbl}', (select count(*) from tbl_{tag_tbl})); 

    with
    piece as (
            -- prepare polygon sections
            select d.polyid,
            -- following may fail by two or more rasons, 
            --  (1) multiband vs touching polygon (ticket 3725),
            --  (2) barely intersecting polygon (ticket 3730) 
            --  (3) something else?
            -- am going to run and let it fail, but record the polyid on failure
            st_clip(r.rast, d.geom) as clp,
            -- safe guarded version that i wrote for postgis 2.3.  hopefully i dont need this anyrmore
            -- st_clip_fuzzy(r.rast, d.geom) as clp,
            d.acq_date_lst
            from rst_{tag_tbl} as r
            inner join
            work_div_oned as d
            on st_intersects(r.rast, d.geom)
    )
    insert into tbl_{tag_tbl} (polyid, v_{tag_var}, f_{tag_var}, acq_date_lst)
    select 
    polyid, 
    val, 
    (cnt::float)/(tcnt::float) as afrac, 
    acq_date_lst 
    from (
            -- record majority class
            select 
            polyid, 
            (pvc).value as val,
            (pvc).count as cnt,
            tcnt,
            acq_date_lst ,
            row_number() over (partition by polyid order by (pvc).count desc) as rnk
            from (
                    -- count pixels grouped by raster value
                    select polyid,
                    st_valuecount(clp) as pvc,
                    st_count(clp) as tcnt,
                    acq_date_lst
                    from (
                            select polyid,
                            st_union(clp) as clp,
                            acq_date_lst
                            from piece
                            group by acq_date_lst, polyid
                    ) bar 
            ) baz
--    ) quz where rnk = 1;
    ) quz ;-- where rnk = 1; -- modified 20190925, extract all LCT
        i := log_checkout(i, (select count(*) from tbl_{tag_tbl}) );
      END;
    $$;
    set client_min_messages to notice;

    -- TODO save rnk==2 as well, and check if i feel confortable picking just rnk1.
    -- flag records with concern.


    do language plpgsql $$ begin
    raise notice 'tool: {tag_tbl} done, %', clock_timestamp();
    end $$;
    """.format( schema=schema, tag_tbl=tag_tbl, tag_var=tag_var)

    return cmd

def mkcmd_insert_table_continuous(tag_tbl, tag_vars, schema):

    varnames = ['v_{0}'.format(_) for _ in tag_vars]
    nvar = len(varnames)

    expr_lst = ', '.join(varnames)
    expr_mean = ', \n'.join('(stats{seq}).mean as val{seq}'.format( seq =  _+1) for _ in range(nvar))
    expr_summary = ', \n'.join('st_summarystatsagg(p.clp, {seq}, true) as stats{seq}'.format(seq =  _+1) for _ in range(nvar))

    cmd = """
    set search_path to "{schema}",raster,public;

    set client_min_messages to warning;

    DO LANGUAGE plpgsql $$ 
      DECLARE
        i bigint;
      BEGIN 
        i := log_checkin('join {tag_tbl}', 'tbl_{tag_tbl}', (select count(*) from tbl_{tag_tbl})); 

    with
    piece as (
            -- prepare polygon sections
            select d.polyid,
            -- following may fail by two or more rasons, 
            --  (1) multiband vs touching polygon (ticket 3725),
            --  (2) barely intersecting polygon (ticket 3730) 
            --  (3) something else?
            -- am going to run and let it fail, but record the polyid on failure
            st_clip(r.rast, d.geom) as clp, 
            -- safe guarded version that i wrote for postgis 2.3.  hopefully i dont need this anyrmore
            --st_clip_fuzzy(r.rast, d.geom) as clp, 
            d.acq_date_lst
            from rst_{tag_tbl} as r
            inner join
            work_div_oned as d
            on st_intersects(r.rast, d.geom)
    ) 
    insert into tbl_{tag_tbl} (polyid, {expr_lst}, acq_date_lst) 
    select 
    polyid, 
    {expr_mean},
    acq_date_lst
    from (
            -- calculate raster stats
            select 
            p.polyid,
            {expr_summary},
            p.acq_date_lst
            from piece as p
            group by p.polyid, p.acq_date_lst
    ) foo 
    ; 

        i := log_checkout(i, (select count(*) from tbl_{tag_tbl}) );
      END;
    $$;



    set client_min_messages to notice;


    do language plpgsql $$ begin
    raise notice 'tool: {tag_tbl} done, %', clock_timestamp();
    end $$;
    """.format(
            schema=schema,
            tag_tbl=tag_tbl,
            expr_lst=expr_lst,
            expr_mean=expr_mean,
            expr_summary=expr_summary,
            )

    return cmd

def mkcmd_insert_table_polygons(tag_tbl, tag_var, variable_in, schema):
    cmd = """
    set search_path to "{schema}",raster,public;

    DO LANGUAGE plpgsql $$ 
      DECLARE
        i bigint;
      BEGIN 
        i := log_checkin('join {tag_tbl}', 'tbl_{tag_tbl}', (select count(*) from tbl_{tag_tbl})); 
    
        with crs as (
        select d.polyid, r.{variable_in} from rst_{tag_tbl} r 
                right join work_div_oned as d
                on st_intersects(r.geom, st_centroid(d.geom))
                )
                insert into tbl_{tag_tbl} (polyid, v_{tag_var})
                select * from crs;
        i := log_checkout(i, (select count(*) from tbl_{tag_tbl}) );
      END;
    $$;

    do language plpgsql $$ begin
    raise notice 'tool: {tag_tbl} done, %', clock_timestamp();
    end $$;
    """.format(

            schema=schema,
            tag_tbl=tag_tbl,
            tag_var=tag_var,
            variable_in=variable_in,
            )
    return cmd
    

def mkcmd_insert_table_output(tag_tbls, fldnames, dctfldtbl, schema):
    tblname = 'out_' + '_'.join(tag_tbls)

    flddsts = ', '.join(fldnames)

    fldsrcs = ', '.join('tbl_{0}.{1}'.format( dctfldtbl[_], _)
            for _ in fldnames)
    rstnames = set('tbl_{0}'.format(dctfldtbl[_]) for _ in fldnames)
    joins = '\n'.join('left join {rst} on d.polyid = {rst}.polyid'.format(rst = _) for _ in rstnames)


    cmd = """
    insert into {tblname} (polyid, fireid, geom, cen_lon, cen_lat, acq_date_lst, area_sqkm, {flddsts})
    select d.polyid, d.fireid, d.geom, st_x(d.centroid) cen_lon, st_y(d.centroid) cen_lat, d.acq_date_lst, d.area_sqkm, 
    {fldsrcs}
    from (
    select polyid, fireid, geom, acq_date_lst, area_sqkm, st_centroid(geom) centroid from work_div_oned) d
    {joins}
    ;

    do language plpgsql $$ begin
    raise notice 'tool: output table done, %', clock_timestamp();
    end $$;
    """.format(
            tblname=tblname,
            flddsts = flddsts,
            fldsrcs = fldsrcs,
            joins = joins,
            )

    return cmd
