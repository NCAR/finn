import datetime
from subprocess import Popen

from run_step1a import get_first_last_day

ver = 'dev1'

def main(tag_af, rasters, first_day=None, last_day=None, run_prep=True, run_work=True, algorithm_merge_aggressive_threshold_tree_cover=50):

    schema = 'af_{0}'.format( tag_af )


    # rasters is list of dicts
    # [ { 'tag': tag for the raster dataset,
    #     'kind': either 'thematic', 'continuous', 'polygons'
    #     'variables': list of variable names (optional)}
    #   } ,...]
    # when variables is omitted the raster dataset tag is going to be used to identify variable

    tag_rsts = [_['tag'] for _ in rasters]

    scrname_prep = 'stepvcf_prep_{0}_{1}.sql'.format('_'.join(tag_rsts), ver)
    scrname_work = 'stepvcf_work_{0}_{1}.sql'.format('_'.join(tag_rsts), ver)
    scrname_post = 'stepvcf_post_{0}_{1}.sql'.format('_'.join(tag_rsts), ver)

    #for tag_rst in tag_rsts:
    cmd_prep = 'set search_path to "{0}",public;\n'.format( schema )
    cmd_work = 'set search_path to "{0}",raster,public;\n'.format( schema )
    cmd_post = 'set search_path to "{0}",public;\n'.format( schema )

    cmd_work += mkcmd_create_table_oned()

    tag_tbls = []
    fldnames = []
    fldtypes = []
    dctfldtbl = {}
    # rstinfo should have 'modvcf_YYYY'
    for rstinfo in rasters:
        if not rstinfo['tag'].startswith('modvcf_'): continue
        mytag_tbl = 'modtree_' + rstinfo['tag'][7:]
        mytag_rst = rstinfo['tag']
        myvars = ['tree']
        cmd_prep += mkcmd_create_table_continuous(mytag_tbl, myvars, schema)
        print('calling', mytag_tbl, mytag_rst, myvars, schema, rstinfo)
        cmd_work += mkcmd_insert_table_continuous(mytag_tbl, mytag_rst, myvars, schema)
        tag_tbls += [mytag_tbl]
        fldnames += ['v_'+_ for _ in myvars]
        fldtypes += (['double precision'] * len(myvars))
        dctfldtbl.update([('v_tree', tag_tbls[-1]) for _ in myvars])

        cmd_prep += '\n--\n-- Prepare table for output\n--\n'
        cmd_work += '\n--\n-- Gather restuls to output\n--\n'
        cmd_prep += mkcmd_create_table_output(tag_tbls, fldnames, fldtypes, schema)
        cmd_work += mkcmd_insert_table_output(tag_tbls, fldnames, dctfldtbl, schema)

    cmd_post += f'''
-- copy over attributes to work_pnt
with t as (
    select fireid,v_tree
    from 
)
UPDATE work_pnt p SET
alg_agg = CASE WHEN t.v_tree >= {algorithm_merge_aggressive_threshold_tree_cover} THEN 1
          ELSE 2
          END
from work_tree t
where 
p.fireid1 = t.fireid;

UPDATE work_lrg1 l SET
alg_agg = CASE WHEN t.v_tree >= {algorithm_merge_aggressive_threshold_tree_cover} THEN 1
          ELSE 2
          END
from work_tree t
where 
l.fireid = t.fireid;
'''

    #print(cmd_prep)
    with open(scrname_prep, 'w') as f:
        f.write(cmd_prep)
    #print(cmd_work)
    with open(scrname_work, 'w') as f:
        f.write(cmd_work)
    with open(scrname_post, 'w') as f:
        f.write(cmd_post)

    # run the prep script
    if run_prep:

        print("starting prep: {0}".format( datetime.datetime.now()))
        p = Popen(
                ['psql']
                + ['-f', scrname_prep]
                )
        p.communicate()

    if run_work: 

        if first_day is None or last_day is None:
            first_day, last_day = get_first_last_day(tag_af)

        dt0 = first_day
        dt1 = last_day + datetime.timedelta(days=1)

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

        print("starting post: {0}".format( datetime.datetime.now()))
        p = Popen(
                ['psql']
                + ['-f', scrname_post]
                )
        p.communicate()


    if True:
        # merge, export
        pass

#def mkcmd_create_table_output(tag_tbls, fldnames, fldtypes, schema):

def mkcmd_create_table_oned():
    cmd = """    
    -- made by mkcmd_create_table_oned()
    do language plpgsql $$ begin
            raise notice 'tool: start, %', clock_timestamp();
    end $$;

    -- hold onto date being processed
    drop table if exists tmp_oned;
    create temporary table tmp_oned ( oned text );
    insert into tmp_oned (oned) values(:oned);


    -- pick only one day data
    drop table if exists work_lrg_oned;
    create temporary table work_lrg_oned (
            fireid integer,
            geom_lrg geometry,
            acq_date_use date,
            ndetect integer,
            area_sqkm double precision
            );

    insert into work_lrg_oned (fireid, geom_lrg, acq_date_use, ndetect, area_sqkm)
    select fireid, geom_lrg, acq_date_use, ndetect, area_sqkm
    from work_lrg1 where acq_date_use = :oned::date;
    do language plpgsql $$
            declare
            cur cursor for select acq_date_use from work_lrg_oned limit 1;
            rec record;
            begin
            raise notice 'tool: oneday done, %', clock_timestamp();
            open cur;
            fetch cur into rec;
            raise notice 'tool: oned is, %', rec.acq_date_use;
    end $$;
    """
    return cmd

def mkcmd_create_table_continuous(tag_tbl, tag_vars, schema):
    tblname = 'tbl_{0}'.format( tag_tbl )
    varnames = ['v_{0}'.format(_) for _ in tag_vars]
    vardefs = ['{0} double precision'.format(  _ ) for _ in varnames]
    cmd = """
    -- made by mkcmd_create_table_continuous()
drop table if exists "{schema}"."{tblname}";
create table "{schema}"."{tblname}" (
    fireid integer,
    {vardefs},
    acq_date_use date
    );
-- clean the left over log if any
select log_purge('join {tag_tbl}'); """.format(   schema=schema, tblname=tblname, vardefs=', '.join(vardefs), tag_tbl=tag_tbl )
    return cmd


def mkcmd_insert_table_continuous(tag_tbl, tag_rst, tag_vars, schema):

    varnames = ['v_{0}'.format(_) for _ in tag_vars]
    nvar = len(varnames)

    expr_use = ', '.join(varnames)
    expr_mean = ', \n'.join('(stats{seq}).mean as val{seq}'.format( seq =  _+1) for _ in range(nvar))
    expr_summary = ', \n'.join('st_summarystatsagg(p.clp, {seq}, true) as stats{seq}'.format(seq =  _+1) for _ in range(nvar))

    cmd = """
    -- made by mkcmd_insert_table_continuous()
    -- tag_tbl={tag_tbl}, tag_rst={tag_rst}
    set search_path to "{schema}",raster,public;

    set client_min_messages to warning;

    DO LANGUAGE plpgsql $$ 
      DECLARE
        i bigint;
      BEGIN 
        i := log_checkin('join {tag_tbl}', 'tbl_{tag_tbl}', (select count(*) from tbl_{tag_tbl}), (select oned from tmp_oned)); 

    with
    piece as (
            -- prepare polygon sections
            select d.fireid,
            -- following may fail by two or more rasons, 
            --  (1) multiband vs touching polygon (ticket 3725),
            --  (2) barely intersecting polygon (ticket 3730) 
            --  (3) something else?
            -- am going to run and let it fail, but record the polyid on failure
            st_clip(r.rast, d.geom_lrg) as clp, 
            -- safe guarded version that i wrote for postgis 2.3.  hopefully i dont need this anyrmore
            --st_clip_fuzzy(r.rast, d.geom_lrg) as clp, 
            d.acq_date_use
            from rst_{tag_rst} as r
            inner join
            work_lrg_oned as d
            on st_intersects(r.rast, d.geom_lrg)
    ) 
    insert into tbl_{tag_tbl} (fireid, {expr_use}, acq_date_use) 
    select 
    fireid, 
    {expr_mean},
    acq_date_use
    from (
            -- calculate raster stats
            select 
            p.fireid,
            {expr_summary},
            p.acq_date_use
            from piece as p
            group by p.fireid, p.acq_date_use
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
            tag_rst=tag_rst,
            expr_use=expr_use,
            expr_mean=expr_mean,
            expr_summary=expr_summary,
            )

    return cmd

def mkcmd_create_table_output(tag_tbls, fldnames, fldtypes, schema):
    tblname = 'work_tree'
    valdefs = ['{0} {1}'.format(n, t)
            for (n, t) in zip(fldnames, fldtypes)]

    cmd = """
    -- made by mkcmd_create_table_output()
drop table if exists "{schema}"."{tblname}";
create table "{schema}"."{tblname}" (
    fireid integer,
    geom_lrg geometry,
    acq_date_use date,
    ndetect integer,
    area_sqkm double precision,
    v_tree double precision
    );""".format(
            schema=schema,
            tblname=tblname,
            )
    return cmd


def mkcmd_insert_table_output(tag_tbls, fldnames, dctfldtbl, schema):
    tblname = 'work_tree'

    flddsts = ', '.join(fldnames)

    fldsrcs = ', '.join('tbl_{0}.{1}'.format( dctfldtbl[_], _)
            for _ in fldnames)
    rstnames = set('tbl_{0}'.format(dctfldtbl[_]) for _ in fldnames)
    joins = '\n'.join('left join {rst} on d.fireid = {rst}.fireid'.format(rst = _) for _ in rstnames)


    cmd = """
    -- made by mkcmd_insert_table_output()
    DO LANGUAGE plpgsql $$ 
      DECLARE
        i bigint;
      BEGIN 
        i := log_checkin('merge all', '{tblname}', (select count(*) from {tblname}),(select oned from tmp_oned) ); 

    insert into {tblname} (fireid, geom_lrg, acq_date_use, ndetect, area_sqkm, v_tree)
    select d.fireid, d.geom_lrg, d.acq_date_use, d.ndetect, d.area_sqkm, 
    {fldsrcs}
    from (
    select fireid, geom_lrg, acq_date_use, ndetect, area_sqkm from work_lrg_oned) d
    {joins}
    ;
        i := log_checkout(i, (select count(*) from {tblname}) );
      END;
    $$;

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
