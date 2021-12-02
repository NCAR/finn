
import psycopg2

import os


def work(schema0, schema, tblname):

    conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])
    cur = conn.cursor()


    def prep(schema, tblname):

        cur.execute(f'SELECT DISTINCT acq_date_use FROM "{schema0}"."{tblname}"')
        days = sorted(_[0] for _ in cur.fetchall())

        sql = f''' 
        ALTER TABLE "{schema}"."{tblname}"
        ADD COLUMN IF NOT EXISTS fireid0 integer
        '''
        cur.execute(sql)
        conn.commit()

        return days

    def work_oned(dy, schema0, schema, tblname):


        # get unique subdivided polygons
        sql = f'''
        CREATE TEMPORARY TABLE tbl_div0
        AS 
        SELECT DISTINCT geom, fireid, acq_date_use
        FROM "{schema0}"."{tblname}"
        WHERE acq_date_use = '{dy}'
        '''
        cur.execute(sql)

        # dissole them
        sql= f'''
        CREATE TEMPORARY TABLE tbl_lrg0
        AS 
        SELECT ST_union(geom) as geom, fireid, acq_date_use
        FROM tbl_div0
        GROUP BY fireid, acq_date_use;
        '''
        cur.execute(sql)

        # gist index
        sql = f'''
        CREATE INDEX IF NOT EXISTS tbl_lrg0_gix
        ON tbl_lrg0
        USING gist( geom )'''
        cur.execute(sql)

        #  subdiv polygon of targets
        sql = f'''
        CREATE TEMPORARY TABLE tbl_div
        AS 
        SELECT DISTINCT geom, polyid, acq_date_use, null::integer fireid0
        FROM "{schema}"."{tblname}"
        WHERE acq_date_use = '{dy}'
        '''
        cur.execute(sql)

        # gix
        sql = f'''
        CREATE INDEX tbl_div_gix
        ON tbl_div
        USING gist( geom )'''
        cur.execute(sql)

        # identify the large polygon (fireid0)
        sql = f'''
        UPDATE tbl_div t
        SET fireid0 = o.fireid
        FROM tbl_lrg0 o
        WHERE 
        o.geom && t.geom
        AND ST_intersects(o.geom, t.geom)
        '''
        cur.execute(sql)


        # copy the value over to the original table
        sql = f'''
        UPDATE "{schema}"."{tblname}" t
        SET fireid0 = d.fireid0
        FROM tbl_div d
        WHERE t.polyid = d.polyid
        '''
        cur.execute(sql)

        for tbl in ('tbl_div0', 'tbl_lrg0', 'tbl_div'):
            cur.execute(f'DROP TABLE {tbl}')

        conn.commit()

        # clean


    days = prep(schema, tblname)
    print(f'''
schema0: {schema0}
schema: {schema}
tblname: {tblname}
ndays: {len(days)}
'''
)

    for dy in days:
        print(f'{dy}')
        work_oned(dy, schema0, schema, tblname)






