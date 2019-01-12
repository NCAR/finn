import subprocess, glob, os
import six
import numpy as np
from pyproj import Proj
from bs4 import BeautifulSoup
import ogr
import requests
from urllib.parse import urlparse

default_droot = 'downloads'

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

def download_only_needed(url, pnts, droot=default_droot):
    """get list of points and grab only tiles that cover points"""

    # based on lon/lat of points, identify tiles needed
    tiles = find_needed_tiles(pnts)

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

def get_filelist(url):
    """download one page, look for <a href and get list of files"""
    
    # get the index.html
    soup = BeautifulSoup(requests.get(url).text, features='html.parser')

    # get all the <a href= in the page
    filelist = [_['href'] for _ in soup.findAll('a', href=True)]

    # purge ones with / which may go to somewhere
    filelist = [_ for _ in filelist if '/' not in _]
    return filelist

    

def find_needed_tiles(lnglat):
    
    if isinstance(lnglat, six.string_types):
        # assume path
        if not os.path.exists(lnglat):
            # its not path either
            raise RuntimeError('lnglat is not filepath: %s' % lnglat)
        lnglat = ogr.Open(lnglat)

    if isinstance(lnglat, ogr.DataSource):
        print('reading shp file ...', end=' ', flush=True)
        coords = np.array([(_.geometry().GetX(), _.geometry().GetY())   for _ in lnglat.GetLayer(0)])
        print('Done')
        lnglat = coords

    return find_needed_tiles_slave(lnglat)


def find_needed_tiles_slave(lnglat):
    """given point features identify MODIS tiles needed"""

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

    def unique_rows(a):
        a = np.ascontiguousarray(a) 
        unique_a = np.unique(a.view([('', a.dtype)]*a.shape[1])) 
        return unique_a.view(a.dtype).reshape((unique_a.shape[0], a.shape[1]))


    # get  the unique tiles
    o = unique_rows(o)

    # put the results in to hXXvXX format
    o = ['h%02dv%02d' % (_[0], _[1]) for _ in o]

    return o

def tester1():



    import ogr
    #
    #
    oo1 = find_needed_tiles(np.array([[-180,0],[-90,0],[0,0],[90,0],[180,0]]))
    oo2 = find_needed_tiles(np.array([[-180,0],[-180,30], [-180,60],[-180,90]]))
    oo3 = find_needed_tiles(np.array([[0,0],[0,30], [0,60],[0,90]]))

    ds = ogr.Open('./downloads/firms/na_2012/fire_archive_M6_34602.shp')
    coords = np.array([(_.geometry().GetX(), _.geometry().GetY())   for _ in ds.GetLayer(0)])

    tiles = find_needed_tiles(coords)

def tester2():

    import ogr
    ds = ogr.Open('./downloads/firms/na_2012/fire_archive_M6_34602.shp')
    coords = np.array([(_.geometry().GetX(), _.geometry().GetY())   for _ in ds.GetLayer(0)])

    tiles = find_needed_tiles(coords)

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
