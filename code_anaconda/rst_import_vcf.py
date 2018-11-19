""" Import vegetation continuous fields NO_DATA
i figure that process outside of postgis then import is better done try to
do things in gis.  I looked into:

st_mapalgebra see if it can work on band, but that was very slow

st_translate to project.  having hard time to grab correct set of tiles. i
tied with gist index having shadow geometry in differen projection, but
maybe because of sinusoidal being funky, i had hard time grabbing
meaningful number of raster

so basically falling back to the approach of AQRP, but am a bit smater
(1) merge bands before projection to do things in one shot
(2) use vrt (virtual raster table) and also -te to window out 10 deg by
10 deg projected raster.  it is a pain to create giant raster of entire
globe especially when resolution is 6sec.  we can merge or mosaic later as
wish
"""
import glob
import os
import re
import datetime
import shlex
import subprocess
import gdal
import numpy as np


# hdf layer names
lyrnames = [
    'Percent_Tree_Cover',
    'Percent_NonTree_Vegetation',
    'Percent_NonVegetated'
    ]
# acronym Yoseke used, in the order Yosuke uses store data
shortnames = ['tree', 'herb', 'bare']

# intermediates
tiffopts = ['COMPRESS=LZW', 'TILED=YES']

# destination in db
schema = 'raster'
# tile size in the db
tilesiz_db = 240


def get_sdsname(lyrname, fname):
    """Given hdf file and layer name, find subdataset name. (duplicate)"""
    ds = gdal.Open(fname)
    sdss = ds.GetSubDatasets()

    # find subdataset whose name is ending with :lyrname
    sds = [_ for _ in sdss if _[0][-(len(lyrname)+1):] == (':' + lyrname)]
    try:
        assert len(sds) == 1
    except AssertionError:
        print('cant find subdataset :%s' % lyrname)
        for i, s in enumerate(sdss):
            print(i, s)
        raise

    sds = sds[0]
    sdsname = sds[0]
    return sdsname


def work_import(tifnames, tag):
    """Import raster data into PostGIS. (duplicate)"""
    create_schema = ["psql", "-c", 'CREATE SCHEMA IF NOT EXISTS %s;' % schema]
    subprocess.run(create_schema, stdout=subprocess.PIPE)

    dstname = schema + '.' + '_'.join(['rst', tag])
    drop_table = ["psql", "-c", "DROP TABLE IF EXISTS %s;" % dstname]
    subprocess.run(drop_table, stdout=subprocess.PIPE)

    cmd_prefix = 'raster2pgsql -d -C -s 4326 -I -M -N 255'.split()
    cmd_prefix += ['-t', '%(tilesiz)sx%(tilesiz)s' % dict(tilesiz=tilesiz_db)]
    print('line77')
    tif_paths = glob.glob(os.path.join('proc_modvcf_2016', 'rsp', '*.tif'))
    cmds = [cmd_prefix + [tif] + [dstname] for tif in tif_paths]
    for cmd in cmds:
        out = subprocess.Popen(cmd, stdout=subprocess.PIPE)
        psql = subprocess.Popen(['psql'], stdin=out.stdout,
                                stdout=subprocess.PIPE)


def work_merge(fnames, workdir):
    """For each file, merge three layers into 3 band raster & import."""
    # partial duplicate
    if not os.path.exists(workdir):
        os.makedirs(workdir)

    buf = []

    for fname in fnames:
        rname = os.path.basename(fname)
        tifname = os.path.join(workdir, rname[:-4] + '.tif')
        sdsnames = [get_sdsname(_, fname) for _ in lyrnames]
        tiffopt = ' '.join(['-co %s' % _ for _ in tiffopts])

        params = dict(
            file=tifname,
            opt=tiffopt,
            sds=' '.join(sdsnames)
        )
        cmd = "gdal_merge.py -separate -o %(file)s %(opt)s %(sds)s" % params

        status = os.system(cmd)
        if not status == 0:
            raise RuntimeError('exit status %s, cmd = %s' % (status, cmd))

        buf.append(tifname)
    return buf


def work_math(fnames, dstdir):
    if not os.path.exists(dstdir):
        os.makedirs(dstdir)
    onames = []
    for fname in fnames:
        oname = os.path.join(dstdir,
                             os.path.basename(fname)[:-4] + '.proc.tif')
        print('proc: %s' % oname)
        work_math_one(fname, oname)
        onames.append(oname)
    return onames

def work_math_one(fname, oname):
    # works on 3band raster on tree/herb/bare
    #  pixels with values > 100, convert them into bare unless its nodata
    drv = gdal.GetDriverByName("GTiff")
    ds = gdal.Open(fname, gdal.GA_ReadOnly)
    dso = drv.CreateCopy(oname, ds)

    bands = [ds.GetRasterBand(_) for _ in (1, 2, 3)]
    arr = [_.ReadAsArray() for _ in bands]
    arr[0] = np.where(arr[0] <= 100, arr[0], 0)
    arr[1] = np.where(arr[1] <= 100, arr[1], 0)
    arr[2] = np.where(arr[2] <= 100, arr[2], 100)

    obands = [dso.GetRasterBand(_) for _ in (1, 2, 3)]

    for (b, a) in zip(obands, arr):
        b.WriteArray(a)
    ds = None
    dso = None
    return oname


def work_resample_pieces(tifnames, dstdir, bname, dryrun=False):
    # create vrt first, and then generate tiled warped files
    if not os.path.exists(dstdir):
        os.makedirs(dstdir)

    print('Creating VRT:')
    vrtname = os.path.join(dstdir, 'src.vrt')
    with open('tifnames.txt', 'w') as f:
        f.write('\n'.join(tifnames) + '\n')
        cmd = 'gdalbuildvrt %s -input_file_list %s' % (vrtname, 'tifnames.txt')
        status = os.system(cmd)
        if status != 0:
            raise RuntimeError('exit status %s, cmd = %s' % (status, cmd))

    res = '-tr 0.00166666666666666666666666666667 0.00166666666666666666666666666667'  # 6 sec
    prj = '-t_srs "+proj=longlat +datum=WGS84 +no_defs"'
    tiffopt = ' '.join(['-co %s' % _ for _ in tiffopts])

    onames = []

    for i in range(36):
        for j in range(18):
            te = '-te %d %d %d %d' % (-180 + 10*i,
                                      90 - 10*(j+1),
                                      -180+10*(i+1),
                                      90-10*j)
            oname = os.path.join(dstdir, '.'.join([bname, 'h%02dv%02d' % (i, j), 'tif']))

            cmd = ('gdalwarp %(prj)s %(res)s %(te)s ' + \
                   '-overwrite -r average -dstnodata 255 ' + \
                   '-wo INIT_DEST=NO_DATA -wo NUM_THREADS=ALL_CPUS ' + \
                   '%(tiffopt)s %(fname)s %(oname)s') % dict(fname=vrtname,
                                                             oname=oname,
                                                             tiffopt=tiffopt,
                                                             prj=prj,
                                                             res=res,
                                                             te=te)
            if not dryrun:
                print(cmd)
                subprocess.run(shlex.split(cmd), stdout=subprocess.PIPE)
            onames.append(oname)
    return onames


def main(tag, fnames):
    workdir = './proc_%s' % tag
    logfilename = 'log.%s.txt' % tag
    logfile = open(logfilename, 'w')

    bname = os.path.basename(fnames[0])[:15]
    print('baname: ', bname)
    assert re.match('MOD44B.A\d\d\d\d065', bname)

    # merge
    dir_merge = os.path.join(workdir, 'mrg')
    if True:
        # merge bands first as files
        logfile.write('merge start : %s\n' % datetime.datetime.now().isoformat())
        mrgnames = work_merge(fnames, dir_merge)
        logfile.write('merge finish: %s\n' % datetime.datetime.now().isoformat())
    else:
        print('line211')
        mrgnames = sorted(glob.glob(os.path.join(dir_merge, '*.tif')))

    # resample
    dir_rsmp = os.path.join(workdir, 'rsp')
    if True:
        logfile.write('resmp start : %s\n' % datetime.datetime.now().isoformat() )
        rsmpnames = work_resample_pieces(mrgnames, dir_rsmp, bname)
        logfile.write('resmp finish: %s\n' % datetime.datetime.now().isoformat() )
    else:
        rsmpnames = work_resample_pieces(mrgnames, dir_rsmp, bname, dryrun=True)

    # import
    if True:
        logfile.write('imprt start : %s\n' % datetime.datetime.now().isoformat() )
        work_import(rsmpnames, tag )
        logfile.write('imprt finish: %s\n' % datetime.datetime.now().isoformat() )
    else:
        pass

if __name__ == '__main__':
    import sys
    tag = sys.argv[1]
    fnames = sys.argv[2:]

    main(tag, fnames)
