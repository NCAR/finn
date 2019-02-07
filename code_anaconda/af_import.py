import os
import subprocess
from subprocess import Popen, PIPE
import itertools
import numpy as np
import shlex
import psycopg2

def gdal_vernum_sys():
    """gets gdal verion from command line, not the python binding"""
    p = subprocess.run(['gdal-config', '--version'], stdout=PIPE)
    v = p.stdout.decode()  # eg '2.3.2'
    v = v.split('.')
    o = []
    for x in v:
        try:
            o.append(int(x))
        except ValueError:
            break
    return o



def main(tag, fnames):
    if isinstance(fnames, str):
        fnames = [fnames]
    schema = 'af_' + tag
    cmd = ['psql', '-c', 
            'DROP SCHEMA IF EXISTS "%s" CASCADE;' % schema]
    subprocess.run(cmd, check=True)
    #cmd = 'psql -c "CREATE SCHEMA %s;"' % schema
    cmd = ['psql', '-c', 'CREATE SCHEMA "%s";' % schema]
    print(cmd)
    subprocess.run(cmd, check=True)

    for i,fname in enumerate(fnames):
        tblname = 'af_in_%d' % (i+1)

        dbname = os.environ.get('PGDATABASE', 'finn')
        cmd = 'ogr2ogr -progress -f PostgreSQL -overwrite'.split()
    #    if 'PGUSER' in os.environ: conn['user'] = os.environ['PGUSER']
        #cmd += [ "PG:dbname='finn' user='postgres' password='finn'" ]
        cmd += [ "PG:dbname='%s'" % dbname]
        vn = gdal_vernum_sys()
        if (vn[0] > 2 or vn[0] == 2 and vn[1] >= 4):
            cmd += '-lco SPATIAL_INDEX=GIST'.split()
        else:
            cmd += '-lco SPATIAL_INDEX=YES'.split()
        cmd += ('-lco SCHEMA='+schema).split()
        cmd += ('-lco GEOMETRY_NAME=geom').split()  # match with what shp2pgsql was doing
        cmd += ('-lco FID=gid').split()  # match with what shp2pgsql was doing
        cmd += ['-nln', tblname]
        cmd += [fname]
        print('\ncmd:\n%s\n' % ' '.join(cmd))
        print(cmd)
        subprocess.run(cmd, check=True)
#            p1 = Popen(cmd)#, stdout=PIPE)
    #    p2 = Popen(['psql',], stdin=p1.stdout, stdout = fo)
    #    print( p2.communicate())
#            p1.communicate()

def check_raster_contains_fire(rst, fire):
    dct = dict(rst=rst, fire=fire)
    conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])

    # count # of fires is af_in file
    cur = conn.cursor()
    cur.execute("""select count(*) from %(fire)s;""" % dct)
    nfire = cur.fetchall()[0][0]

    # see if skel file exists
    # got this technique from here 
    # https://stackoverflow.com/questions/20582500/how-to-check-if-a-table-exists-in-a-given-schema
    # hope this works...
    has_skel = True
    try:
        cur.execute("""SELECT '%(rst)s'::regclass;""" % dct)
    except psycopg2.ProgrammingError:
        has_skel = False
        ncnt = 0

    if has_skel:
        cur.execute("""select count(*) from %(rst)s a, %(fire)s b where  ST_Contains(a.geom , b.geom);""" % dct)
        ncnt = cur.fetchall()[0][0]

    nob = nfire - ncnt
    return dict(n_fire=nfire, n_containd = ncnt, n_not_contained= nob)

def get_lnglat(schema, combined=False):
    # go over af_in files in the schema, and return info

    conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])
    cur = conn.cursor()

    # go over each af_in table
    lst = []
    for i in itertools.count():
        tbl = 'af_in_%d' % (i+1)
        st = '%s.%s' % (schema, tbl)
        try:
            cur.execute("""SELECT '%s'::regclass;""" % st)
        except psycopg2.ProgrammingError as e:
            # no such table
            if i == 0:
                # something is wrong..., no af_in at all??
                raise e
            break
        cur.execute("""select longitude::float,latitude::float from %s;""" % st)
        lnglat = cur.fetchall()
        lnglat = np.array([[float(x) for x in r] for r in lnglat])
        lst.append(lnglat)
        
    if combined:
        lst = np.vstack(lst)
    return lst


def get_dates(schema, combined=False):
    # go over af_in files in the schema, and return info

    conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])
    cur = conn.cursor()

    # go over each af_in table
    lst = []
    for i in itertools.count():
        tbl = 'af_in_%d' % (i+1)
        st = '%s.%s' % (schema, tbl)
        try:
            cur.execute("""SELECT '%s'::regclass;""" % st)
        except psycopg2.ProgrammingError as e:
            # no such table
            if i == 0:
                # something is wrong..., no af_in at all??
                raise e
            break
        cur.execute("""select acq_date from %s;""" % st)
        dates = cur.fetchall()
        dates = np.array([r[0] for r in dates])
        lst.append(dates)
    if combined:
        lst = np.concatenate(lst)
    return lst

if __name__ == '__main__':
    import sys
    tag = sys.argv[1]
    fnames = [sys.argv[2]]
    fnames += sys.argv[3:]

    main(tag, fnames)


