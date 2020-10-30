import os
import subprocess
from subprocess import Popen, PIPE
import itertools
import numpy as np
import shlex
import psycopg2
from pathlib import Path

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

        fname = Path(fname)

        if fname.suffix == '.shp':
            # shape file, straight to database
            src = fname
        elif fname.suffix in ('.csv', '.txt'):
            # text file, wrap with vrt (virtual layer)
            if fname.suffix == '.txt':
                orig = 'CSV:' + fname.name
            else:
                orig = fname.name
            src = fname.with_suffix('.vrt')
            with open(src, 'w') as vrt:
                vrt.write(
                f"""
<OGRVRTDataSource>
    <OGRVRTLayer name="{fname.stem}">
        <SrcDataSource relativeToVRT="1">{orig}</SrcDataSource>
        <OpenOptions><OOI key="AUTODETECT_TYPE">YES</OOI></OpenOptions>
        <GeometryType>wkbPoint</GeometryType>
        <LayerSRS>WGS84</LayerSRS>
        <GeometryField encoding="PointFromColumns" x="longitude" y="latitude"/>
</OGRVRTLayer>
</OGRVRTDataSource>""".strip())
        else:
            raise RuntimeError('Unknwon extenstion for AF file: ' + fname.suffix)


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
        cmd += [str(src)]
        print('\ncmd:\n%s\n' % ' '.join(cmd))
        print(cmd)
        try:
            subprocess.run(cmd, check=True, stderr=PIPE)
        except subprocess.CalledProcessError as err: 
            cmd0 = cmd[0]
            print(f"\nERROR from {cmd0}: \n\n", err.stderr.decode(),)
            raise

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

# Three get_XXX better be restructured, but i am lazy now.
def get_tiles_needed(schema, combined=False):
    # go over af_in files in the schema, and return info
    #print('gtn')

    conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])
    cur = conn.cursor()

    # go over each af_in table
    lst = []
    for i in itertools.count():
        tbl = 'af_in_%d' % (i+1)
        st = '%s.%s' % (schema, tbl)
        #print('gtn:', st)
        try:
            cur.execute("""SELECT '%s'::regclass;""" % st)
        except psycopg2.ProgrammingError as e:
            # no such table
            if i == 0:
                # something is wrong..., no af_in at all??
                raise e
            break

        # do better!!!
        # maybe groupby st_intersect() count() those??
        #
        # METHOD 1: this is one way:
        #
        #    select count(*), w.tilename from af_in_1 a, wireframe w where st_covers(w.wkb_geometry, a.geom) group by w.tilename;
        # 
        # taking 4 min or so for VIIRS 2019.  st_covers is probably better than st_contains, i think it may pick up points on boundary.
        # 
        # METHOD 2: or come up with postgresql function to determine tile based on coordinate
        #
        #     lntlat2tilename(lng, lat)
        #
        #  to do that, 
        #     define srid for sinu
        #       INSERT into spatial_ref_sys (srid, auth_name, auth_srid, proj4text, srtext) 
        #       values ( 9006842, 'spatialreferencing.org', 6842, 
        #              '+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +a=6371007.181 +b=6371007.181 +units=m +no_defs ', 
        #               'PROJCS["Sinusoidal",GEOGCS["GCS_Undefined",DATUM["Undefined",SPHEROID["User_Defined_Spheroid",6371007.181,0.0]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],PROJECTION["Sinusoidal"],PARAMETER["False_Easting",0.0],PARAMETER["False_Northing",0.0],PARAMETER["Central_Meridian",0.0],UNIT["Meter",1.0]]');
        #     get xy coord on sinu
        #
        #        with st_transform(a.geom, 9006842) as g
        #           st_x(g), st_y(g)
        #     then get tile, doing similar to below
        #

        #        # they divide longitude (-180 to 180) into 36, latitude (-90 to 90) into 18
        #        # fraction of circumfrance (1 for great circle)
        #        o = o / ( 2 * np.pi * 6371007.181 )
        #        #
        #        # divide great cicle into 36
        #        o = o * 36
        #        #
        #        # h, origin is -180 deg
        #        o[:,0] = o[:,0] + 18
        #        #
        #        # v, it is flipped, and covers half of cicle, starting -90 degree
        #        o[:,1] = -o[:,1] + 9
        #        #
        #        # just need integer as tile index
        #        o = np.floor(o).astype(int)
        #
        #  METHOD 2 compatible with my other counting method.  each point get counted at most once.  point on boundary is counted to the tile closer to (lon,lat) = (0,0)
        #
        #  METHOD 1 involves double counting, i think.  But at least it should capture tiles needed, which is primary purpose of this code
        #
        #   I go with METHOD 1 for now.
        #   make sure that rst_import.prep_modis_tile() got called somewhere, to have this wireframe (defining tiles)
        qry = """select count(*), w.tilename from %s a, raster.wireframe w where st_covers(w.wkb_geometry, a.geom) group by w.tilename;""" % st
        #print('gtn: ', qry)
        cur.execute(qry)
        #print('gtn: fetchall')
        tiles = cur.fetchall()
        #print('gtn: np.array')
        tiles = dict((r[1], r[0]) for r in tiles)
        lst.append(tiles)
        
    if combined:
        combined = {}
        for x in lst:
            for k,v in x.items():
                combined[k] = combined.get(k, 0) + v
        return combined
    else:

        return lst

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
        cur.execute("""select distinct acq_date from %s;""" % st)
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


