import subprocess, glob, os
import re
import six
import numpy as np
from pyproj import Proj
from bs4 import BeautifulSoup
try:
    import ogr
except ImportError:
    from osgeo import ogr
import requests
from urllib.parse import urlparse
import modis_tile
import psycopg2
from importlib import reload
from pathlib import Path


import af_import



default_droot = 'downloads'
schema = 'raster'  # modis tile shape, post it to here

def download_all(url, droot=default_droot):
    """download everything in a direcotry (using wget --recursive --noparent)"""

    # all files goest to subdirectory of 'downloads' dir, with path like
    # sitename/path/to/filename.hdf

    cmd = 'wget -nc --recursive --no-parent'.split()
    cmd.extend(['--user', os.environ['EARTHDATAUSER']])
    cmd.extend(['--password', os.environ['EARTHDATAPW']])
    cmd.extend(['-P', droot])
    cmd.append(url)
    subprocess.run(cmd)

def download_one(url, droot=None, ddir=None):
    """download list of files but put the same dir as download all would"""


    cmd = ['wget', '-nc']

    if not ddir is None:
        # if ddir is specified, put file there
        cmd.extend(['--no-directories', '-P', ddir])
    else:
        # if not, use droot, and mirror the dir structure
        if droot is None:
            droot = default_droot
        cmd.extend(['--force-directories', '-P', droot])
    cmd.extend(['--user', os.environ['EARTHDATAUSER']])
    cmd.extend(['--password', os.environ['EARTHDATAPW']])
    cmd.append(url)
    subprocess.run(cmd, check=True)

def download_only_needed(url, tiles=None, region=None, region_knd=None, droot=default_droot):
    """get list of tiles or points and grab only tiles that cover points"""

    if tiles is None:
        if region is None:
            raise RuntimeError('have to specify either tiles or region')
        # based on lon/lat of points, identify tiles needed
        tiles = find_needed_tiles(data=region, knd=region_knd, return_details=False)

    # get list of all files from the url
    flst = get_filelist(url)

    # subset files to only that is needed
    files_needed = [_ for _ in flst if any(t in _ for t in tiles)]

    print(droot)

    # get them one by one
    for fn in files_needed:
        myurl = url.rstrip('/') + '/' + fn
        print(myurl)
        download_one(myurl, droot)


def purge_corrupted(ddir, url=None):
    """go throudh all the hdf files in the dir, and delete the hdf/xml file if it appears corrupt"""

    fnames = sorted(glob.glob(os.path.join(ddir, '*.hdf')))
    for fn in fnames:
        print(fn + ' ...', end=' ')
        if check_downloads(fn):
            # good
            print('OK')
        else:
            # TODO make sure it's actually deleted.  say something or raise if it didnt
            os.remove(fn)
            try:
                os.remove(fn + '.xml')
            except: pass

            if url is None:
                print('corrupted, purged')
            else:
                # if i know url to get the file, i can try get it again
                fn2 = os.path.basename(fn)

                myurl = url.rstrip('/') + '/' + fn2
                print('corrupted, downloading again')
                print(myurl)
                download_one(myurl, ddir=ddir)
                download_one(myurl + '.xml', ddir=ddir)


def check_downloads(fname, get_cksum=None):
    """test checksum of a file against .xml file"""
    if get_cksum is None:
        def earthdata_cksum(fname):
            # assume that the data file comes with xml file
            xname = fname + '.xml'
            soup = BeautifulSoup(open(xname, 'r'), 'html.parser')
            cksum, filsz = [soup.findAll(_)[0].contents[0] for _ in ('checksum', 'filesize')]
            return cksum, filsz
        get_cksum = earthdata_cksum
    cksum0 = ['0','0']
    try:
        cksum0 = get_cksum(fname)
    except:
        pass

    p = subprocess.Popen(['cksum', fname], stdout=subprocess.PIPE)
    cksum = p.stdout.read()
    p.communicate()
    cksum = [_.decode() for _ in cksum.split()[:2]]

    if all((p)==(q) for (p,q) in zip(cksum0, cksum)):
        return True
    else:
        return False

def get_extent(dsname):
    """utility routine to get extend of ogr dataset"""
    dsname = Path(dsname)
    if dsname.suffix in ('.csv', '.txt'):
        dsname = af_import.mk_vrt(dsname)
    if not dsname.is_file:
        raise RuntimeError(f'file doesnt exist: {str(dsname)}')
    ds = ogr.Open(str(dsname))
    if ds is None:
        raise RuntimeError(f'cannot open {str(dsname)}')
    ext =ds.GetLayer().GetExtent()
    del ds

    return ext

def get_filelist(url):
    """download one page, look for <a href and get list of files"""
    soup = BeautifulSoup(requests.get(url).text, features='html.parser')


    r = requests.get(url)
    # catch anything but OK'
    if r.status_code != 200:
        r.raise_for_status()
    
    # get the index.html
    try:
        soup = BeautifulSoup(r.text, features='html.parser')
    except:
        print("\n\nERROR:\nfailed url: " + url)
        raise

    # get all the <a href= in the page
    filelist = [_['href'] for _ in soup.findAll('a', href=True)]

    # purge ones with / which may go to somewhere
    filelist = [_ for _ in filelist if '/' not in _]
    return filelist

def find_table_indb(schema, table):
    st = '"%s"."%s"' % (schema, table)
    conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])
    cur = conn.cursor()
    try:
        cur.execute("""SELECT '%s'::regclass;""" % st)
    except psycopg2.ProgrammingError as e:
        # no such table
        return False
    return True

def find_tiles_indb(data, knd='lnglat', tag_lct=None, tag_vcf=None):

    tiles = find_needed_tiles(data, knd, return_details=True)


    if isinstance(tiles, list):
        # join into one dict if 'tiles' is list of dict
        def append(a, b):
            for k,v in b.items():
                if k in a:
                    vv = a[k]
                    vv['count'] += v['count']
                else:
                    a[k] = v

        my_tiles = dict()
        for x in tiles:
            append(my_tiles, x)
        tiles = my_tiles

    assert isinstance(tiles, dict)

    # get name of tiles which is aleady in db
    re_tileid = re.compile('\.(h\d\dv\d\d)\.')
    def tileindb(tag):
        conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])
        cur = conn.cursor()
        st = 'raster."skel_rst_%s"' % tag
        try:
            cur.execute("""SELECT '%s'::regclass;""" % st)
        except psycopg2.ProgrammingError as e:
            # no such table
            return []

        cur.execute("""select name from raster."skel_rst_%s";""" % tag)
        tiles = [_[0] for _ in cur.fetchall()]
        tiles = [re_tileid.search(_) for _ in tiles]
        assert all(tiles)
        tiles = [_.groups()[0] for _ in tiles]
        return tiles

    tileindb_lct = tileindb(tag_lct)
    tileindb_vcf = tileindb(tag_vcf)

    # count of AF points:
    n_tot = 0  #total
    n_ok = 0 # either tile is in db, or no tile to start with (ocean)
    n_need = 0 # need to be downloaded
    # name of all tiles that is needed to cover fire, but only ones that's actually have LCT/VCF raster tile
    tiles_required_lct = []
    tiles_required_vcf = []
    # name of tiles that is included above but not yet imported into db
    tiles_missing_lct = []
    tiles_missing_vcf = []
    for k in tiles:
        n_tot += tiles[k]['count']
        mis=False
        if tiles[k]['av_lct']:
            tiles_required_lct +=[k]
            if k not in tileindb_lct:
                mis=True
                tiles_missing_lct +=[k]
        if tiles[k]['av_vcf']:
            tiles_required_vcf +=[k]
            if k not in tileindb_vcf:
                mis=True
                tiles_missing_vcf +=[k]
        if mis:
            n_need += tiles[k]['count']
        else:
            n_ok += tiles[k]['count']
    return dict(n_tot=n_tot, n_ok=n_ok, n_need=n_need, 
            tiles_missing_lct=tiles_missing_lct, 
            tiles_missing_vcf=tiles_missing_vcf, 
            tiles_required_lct=tiles_required_lct, 
            tiles_required_vcf=tiles_required_vcf, 
            )
            


def find_needed_tiles(data, knd='lnglat', return_details=False):
    
    is_poly = False
    def tiles_av(tiles):
        tiles = dict((k,dict(
            count=v, 
            av_lct = k in modis_tile.tiles_lct, 
            av_vcf = k in modis_tile.tiles_vcf,
            )
            ) for (k,v) in tiles.items())
        return tiles


    if knd == 'lnglat':
        lnglat = data

    elif knd == 'ds':

        ds = data
        # can be a path to ogr data source file
        if isinstance(ds, six.string_types):
            if not os.path.exists(ds):
                raise RuntimeError('ds doesnt exist: %s' % ds)
            # its not path either
            ds = ogr.Open(ds)

        if not isinstance(ds, ogr.DataSource):
            raise RuntimeError('ds is not ogr Data source or path' % repr(ds))

        lyr = ds.GetLayer()
        geomtyp = lyr.GetGeomType()
        if geomtyp == ogr.wkbPoint:
            print('reading shp file ...', end=' ', flush=True)
            coords = np.array([(_.geometry().GetX(), _.geometry().GetY())   for _ in lnglat.GetLayer(0)])
            print('Done')
            lnglat = coords
        elif geomtyp == ogr.wkbPolygon:
            # its polygon feaure
            is_poly = True

    elif knd == 'wkt': 
        wkt = data
        geom = ogr.CreateGeometryFromWkt(wkt)
        if geom is None:
            raise RuntimeError('wkt unrecognized: %s' % wkt)
        else:
            if geom.GetGeometryType() == ogr.wkbPolygon:
                is_poly = True
                lnglat = geom
            else:
                raise RuntimeError('wkt in unsopported geomtype: %s' % geom.GetGeometryName()) 

    elif knd == 'schema':
        schema = data
        reload(af_import)
        if return_details:
            
            tiles = af_import.get_tiles_needed(schema, combined=False)

            # list of dict
            tiles = [tiles_av(_) for _ in tiles]
            return tiles
            
        else:
            tiles = af_import.get_lnglat(schema, combined=True)
            
            # list of tile names
            return tiles

    else:
        raise('Unknown knd: %s' % knd)


    if is_poly:
        tiles =  find_needed_tiles_polygons(lnglat,return_counts=return_details)
    else:
        tiles =  find_needed_tiles_points(lnglat,return_counts=return_details)

    # return list of tile names
    if not return_details: return tiles

    # return dict, keys=tile names, values = dict of count,lct_av,vcf_av
    tiles = tiles_av(tiles)
    return tiles


def find_needed_tiles_polygons(poly,return_counts):
    # retrun either
    #  list of tilenames  
    #    or
    #  dict of tilname:count_of_fire
    from collections import defaultdict

    #fname0 = 'modis_tile_wgs.shp'
    #tiles = modis_tile.main(silent=True)
    #modis_tile.save_as_shp(tiles, fname)

    class Grabber(object):
        def __init__(self):
            self.tiles = modis_tile.main(silent=True)
        def __call__(self, geom):
            o = []
            lyr = self.tiles.GetLayer()
            lyr.SetSpatialFilter(geom)
            for feat in lyr:
                if geom.Intersects(feat.GetGeometryRef()):
                    h = feat.GetField('h')
                    v = feat.GetField('v')
                    o.append((h,v))
            return o

    grabber = Grabber()

    if isinstance(poly, ogr.Geometry):
        oo = grabber(poly)
        oo = dict((_,1) for _ in oo)

    else:
        oo = defaultdict(int)
        if isinstance(poly, ogr.DataSource):
            lyr = poly.GetLayer()
        elif isinstance(poly, ogr.Layer):
            lyr = poly
        for feat in lyr:
            geom = feat.GetGeometryRef()
            o = grabber(geom)
            for x in o:
                oo[x] += 1

    o = ['h%02dv%02d' % (_[0], _[1]) for _ in oo]
    if return_counts:
        o = dict((_,np.nan) for _ in o)
    return o
    


def find_needed_tiles_points(lnglat,return_counts):
    """given point features identify MODIS tiles needed"""
    # retrun either
    #  list of tilenames  
    #    or
    #  dict of tilname:count_of_fire

    # modis sinusoidal, but they may be using sphere
    # see this page https://modis-land.gsfc.nasa.gov/GCTP.html
    # http://spatialreference.org/ref/sr-org/modis-sinusoidal/
    p = Proj('+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +a=6371007.181 +b=6371007.181  +units=m +no_defs') 

    # coordinates on modis sinusoidal 
    o = p(lnglat[:,0], lnglat[:,1])
    o = np.vstack((o[0], o[1])).T


    # they divide longitude (-180 to 180) into 36, latitude (-90 to 90) into 18

    # fraction of circumfrance (1 for great circle)
    o = o / ( 2 * np.pi * 6371007.181 )

    # divide great cicle into 36
    o = o * 36

    # h, origin is -180 deg
    o[:,0] = o[:,0] + 18

    # v, it is flipped, and covers half of cicle, starting -90 degree
    o[:,1] = -o[:,1] + 9

    # just need integer as tile index
    o = np.floor(o).astype(int)

    def unique_rows(a,return_counts):
        a = np.ascontiguousarray(a) 
        return  np.unique(a.view([('', a.dtype)]*a.shape[1]), return_counts) 


    # get  the unique tiles
    if return_counts:
        o,cnt = unique_rows(o,return_counts)
    else:
        o = unique_rows(o,return_counts)

    # put the results in to hXXvXX format
    o = ['h%02dv%02d' % (_[0], _[1]) for _ in o]
    if return_counts:
        o = dict(zip(o, cnt))
    return o

def tester1():



    import ogr
    #
    #
    oo1 = find_needed_tiles(data=np.array([[-180,0],[-90,0],[0,0],[90,0],[180,0]]), knd='lnglat')
    oo2 = find_needed_tiles(data=np.array([[-180,0],[-180,30], [-180,60],[-180,90]]), knd='lnglat')
    oo3 = find_needed_tiles(data=np.array([[0,0],[0,30], [0,60],[0,90]]), knd='lnglat')

    ds = ogr.Open('./downloads/firms/na_2012/fire_archive_M6_34602.shp')
    coords = np.array([(_.geometry().GetX(), _.geometry().GetY())   for _ in ds.GetLayer(0)])

    tiles = find_needed_tiles(data=coords, knd='lnglat')

def tester2():

    import ogr
    ds = ogr.Open('./downloads/firms/na_2012/fire_archive_M6_34602.shp')
    coords = np.array([(_.geometry().GetX(), _.geometry().GetY())   for _ in ds.GetLayer(0)])

    tiles = find_needed_tiles(data=coords,knd='lnglat')

    testurl = 'https://e4ftl01.cr.usgs.gov/MOTA/MCD12Q1.006/2016.01.01/' 
    flst = get_filelist(testurl)

    files_needed = [_ for _ in flst if any(t in _ for t in tiles)]

def tester3():
    # tests the download_only_needed.  Be careful with where the file is saved!!

    import ogr
    print('reading shp file ...', end=' ', flush=True)
    ds = ogr.Open('../downloads/firms/na_2012/fire_archive_M6_34602.shp')
    coords = np.array([(_.geometry().GetX(), _.geometry().GetY())   for _ in ds.GetLayer(0)])
    print('Done')

    testurl = 'https://e4ftl01.cr.usgs.gov/MOTA/MCD12Q1.006/2016.01.01/' 
    download_only_needed(testurl, coords)
#tester3()

def tester4():
    testurl = 'https://e4ftl01.cr.usgs.gov/MOTA/MCD12Q1.006/2016.01.01/' 
    purge_corrupted( './downloads/e4ftl01.cr.usgs.gov/MOTA/MCD12Q1.006/2016.01.01', url = testurl)

#tester4()
