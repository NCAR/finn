""" Import modis raster data
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
import subprocess
import shlex
import itertools

import gdal
import ogr
import osr
from shapely.geometry import Polygon
import shapely
import numpy as np

# supported data category
config_datacat = dict(
        lct = dict( 
            # hdf layer names
            lyrnames = ['LC_Type1'],  # for modis c6 
            # acronym Yosuke used, in the order Yosuke uses store data
            shortnames = ['lct'],
            # extra options for merge
            mrg_opt = [''],
            rsmp_alg = 'mode',
            re_bname = re.compile('^MCD12Q1.A(\d\d\d\d)001'),
            ),
        vcf = dict( 
            # hdf layer names
            lyrnames = [ 
                'Percent_Tree_Cover', 
                'Percent_NonTree_Vegetation', 
                'Percent_NonVegetated' 
                ], 
            # acronym Yosuke used, in the order Yosuke uses store data
            shortnames = ['tree', 'herb', 'bare'],
            # extra options for merg
            mrg_opt = ['-separate'],
            rsmp_alg = 'average',
            re_bname = re.compile('^MOD44B.A(\d\d\d\d)065'),
            ),
        bdt = dict( 
            # hdf layer names
            lyrnames = ['Burn Date'],  # for modis c6 
            # acronym Yosuke used, in the order Yosuke uses store data
            shortnames = ['bdt'],
            # extra options for merge
            mrg_opt = [''],
            rsmp_alg = 'mode',
            re_bname = re.compile('^MCD64A1.A(\d\d\d\d)\d\d\d'),
            ),
)


# intermediates
# set of tiff options i always use
tiffopts = ['COMPRESS=LZW', 'TILED=YES']

# destination in db
schema = 'raster'
# tile size in the db
tilesiz_db = 240

# pyramid levels
#o_lvls = [str(_) for _ in (2,4,8,16,32)]
o_lvls = [str(_) for _ in (32,)]


def get_sdsname(lyrname, fname):
    """Given hdf file and layer name, find subdataset name for the layer."""
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

def censor_sinu(p):
    r = 6371007.181 
    #p[1]/r is latitude in radian
    len_parallel = 2 * np.pi * r * np.cos(p[...,1]/r)
    p[..., 0] = np.where(  np.abs(p[..., 0]) > .5 * len_parallel , .5 * len_parallel * np.sign(p[..., 0]), p[...,0])
    return p



def get_skelton(tifname, dso=None, name_use=None, fn_censor=None):

    if name_use is None: name_use = tifname
    name_use = os.path.basename(name_use)
    ds = gdal.Open(tifname)

    gt = np.array(ds.GetGeoTransform())
    nc = ds.RasterXSize
    nr = ds.RasterYSize

    # get projection
    srs = osr.SpatialReference()
    srs.ImportFromWkt(ds.GetProjection())

    # if its sinusoidal, i know what to do
    if fn_censor is None:
        srs0 = osr.SpatialReference()
        srs0.ImportFromProj4('+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +a=6371007.181 +b=6371007.181  +units=m +no_defs') 
        #print(srs)
        #print(srs0)
        # this IsSame doesnt work...
        if srs.IsSame(srs0):
            # given y coord, i can calculate length of the parallel.
            # if x coord is beyond what's expected, shift to the x bound
            fn_censor = censor_sinu
        else:
            fn_censor = lambda x: x

    # get corners and points along sides


    # points on one side 
    num = 50
    xp = np.rint(np.linspace(0, nc, num+1))
    yp = np.rint(np.linspace(0, nr, num+1))

    # coords along four sides
    xy = np.zeros(((num)*4+1,2))

    xy[(0*num):(1*num),0] = 0
    xy[(0*num):(1*num),1] = yp[:-1]

    xy[(1*num):(2*num),0] = xp[:-1]
    xy[(1*num):(2*num),1] = yp[-1]

    xy[(2*num):(3*num),0] = xp[-1]
    xy[(2*num):(3*num),1] = yp[:0:-1]

    xy[(3*num):(4*num),0] = xp[:0:-1]
    xy[(3*num):(4*num),1] = 0

    xy[(4*num),:]=0

    # inver order so that points go clockwise, somwhow it works better in shapely
    # with original ordering, it failed to fix the shape in siberia ('h22v01'), 
    # for example.  top right tile which tourches boundary seemed to fail
    # better way is to not rely on censor method, which shift out of boundary points
    # horizontally to boundary but also check if vertical correction is needed
    # (move to intersection of side of tile and the boundary), but i just let it 
    # go for now, it is sort of working
    # 
    xy = xy[::-1,:]

    # coords in dataset's coordinate
    xy = np.apply_along_axis(lambda p: (gt[0] + (gt[1:3]*p).sum(), gt[3] + (gt[4:6]*p).sum()), 1, xy)

    # censor points outside of defined area
    xy = fn_censor(xy)

    # remove repeated points (after censoring)
    ok = [0]
    for i in range(1, (xy.shape[0])):
        if not np.array_equal(xy[i-1,:], xy[i,:]):
            ok.append(i)
    xy = xy[ok,:]


    # make it into polygon
    poly = Polygon(xy)
    if not poly.is_valid:
        poly = poly.buffer(0)
        if not poly.is_valid:
            import pdb; pdb.set_trace()
    assert poly.area > 0


    # ogr memory dataset
    if dso is None:
        # create dataset
        drv = ogr.GetDriverByName('Memory')
        dso = drv.CreateDataSource('poly')
        lyr = dso.CreateLayer('',srs,ogr.wkbPolygon)
        lyr.CreateField(ogr.FieldDefn('id',ogr.OFTInteger))
        fdefn = ogr.FieldDefn('name',ogr.OFTString)
        fdefn.SetWidth(255)
        lyr.CreateField(fdefn)

        defn = lyr.GetLayerDefn()
        idn = 1
    else:
        # last record
        lyr = dso.GetLayer()
        defn = lyr.GetLayerDefn()
        idn = lyr.GetFeatureCount()
        idn = max(idn, lyr.GetFeature(idn-1).GetField('id')) + 1

    # add the polygon to the dataset
    feat = ogr.Feature(defn)
    feat.SetField('id', idn)
    feat.SetField('name', name_use)
    geom = ogr.CreateGeometryFromWkb(poly.wkb)
    feat.SetGeometry(geom)
    lyr.CreateFeature(feat)
    feat = geom = None
    lyr = None

    return dso

def test_get_skelton():
    fname = './downloads/e4ftl01.cr.usgs.gov/MOTA/MCD12Q1.006/2016.01.01/MCD12Q1.A2016001.h22v01.006.2018055072419.hdf'
    o = get_skelton(fname)
    assert o.GetLayer().GetFeatureCount() == 1
    import pdb; pdb.set_trace()
    pass

class Intersecter(object):
    def __init__(self, ds):
        from shapely import wkb
        from shapely import ops
        lyr = ds.GetLayer()
        lst = []
        lyr.SetNextByIndex(0)
        for i,feat in enumerate(lyr):
            geom = feat.GetGeometryRef()
            geom = shapely.wkb.loads(geom.ExportToWkb())
            lst.append(geom)
        geom0 = shapely.ops.cascaded_union(lst)
        lyr = geom = None
        self.geom0 = geom0

    def __call__(self, geom):
        try:
            geom2 = self.geom0.intersection(geom)
        except:
            import pdb; pdb.set_trace()
        if geom2 is None:
            import pdb; pdb.set_trace()
        geomx = ogr.CreateGeometryFromWkb(geom2.wkb)
        return geomx


def save_as_shp(ds, oname):
    drv = ogr.GetDriverByName('ESRI Shapefile')
    if os.path.exists(oname):
        drv.DeleteDataSource(oname)
    ds1 = drv.CreateDataSource(oname)

    lyr0 = ds.GetLayer()
    lyr0.SetNextByIndex(0)
    lyr1 = ds1.CreateLayer(lyr0.GetName(), lyr0.GetSpatialRef(), lyr0.GetGeomType())
    defn0 = lyr0.GetLayerDefn()
    for i in range(defn0.GetFieldCount()):
        fdefn = defn0.GetFieldDefn(i)
        lyr1.CreateField(fdefn)
    defn1 = lyr1.GetLayerDefn()

    feat0 = lyr0.GetNextFeature()
    while feat0:
        geom = feat0.GetGeometryRef()
        feat1 = ogr.Feature(defn1)
        feat1.SetGeometry(geom)
        for i in range(defn1.GetFieldCount()):
            feat1.SetField(defn1.GetFieldDefn(i).GetNameRef(), feat0.GetField(i))
        lyr1.CreateFeature(feat1)
        del feat1
        del geom

        feat0 = lyr0.GetNextFeature()
    del lyr0
    del lyr1

    # save
    del ds1



def transform_coordinates(ds, srs, drv=None, oname=None):

    print('trnscoord')
    # create target dataset
    if drv is None:
        drv = ds.GetDriver()
    if oname is None:
        oname = ds.GetName()
    if os.path.exists(oname):
        drv.DeleteDataSource(oname)
    ds1 = drv.CreateDataSource(oname)
    #print(ds1)
    lyr0 = ds.GetLayer()
    lyr0.SetNextByIndex(0)
    lyr1 = ds1.CreateLayer('', srs, ogr.wkbPolygon)
    #print(lyr1)
    defn0 = lyr0.GetLayerDefn()
    #print(defn0)
    #print(defn0.GetFieldCount())
    for i in range(defn0.GetFieldCount()):
        fdefn = defn0.GetFieldDefn(i)
        lyr1.CreateField(fdefn)
    defn1 = lyr1.GetLayerDefn()

    # prepare transform
    srs0 = lyr0.GetSpatialRef()
    coordTrans = osr.CoordinateTransformation(srs0, srs)

    # populate target dataset
    feat0 = lyr0.GetNextFeature()
    while feat0:
        # geometry transormed
        geom = feat0.GetGeometryRef()
        geom.Transform(coordTrans)

        # store feature to target
        feat1 = ogr.Feature(defn1)
        feat1.SetGeometry(geom)
        for i in range(defn1.GetFieldCount()):
            feat1.SetField(defn1.GetFieldDefn(i).GetNameRef(), feat0.GetField(i))
        lyr1.CreateFeature(feat1)
        del geom
        del feat1

        # next feature
        feat0 = lyr0.GetNextFeature()
    
    del lyr0 
    del lyr1
    return ds1 

class Importer(object):

    def __init__(self, datacat = None, fnames = None):
        if datacat is None:
            if fnames is None:
                raise RuntimeError('Importer: init with datacat or fnames')
            bname = os.path.basename(fnames[0])
            for k,v in config_datacat.items():
                m = v['re_bname'].match(bname)
                if m:
                    datacat = k
                    year = m.group(1)
                    break
            if datacat is None:
                raise RuntimeError('Importer: cannot determine data category from file names')

        self.lyrnames = config_datacat[datacat]['lyrnames']
        self.shortnames = config_datacat[datacat]['shortnames']
        self.mrg_opt = config_datacat[datacat]['mrg_opt']
        self.rsmp_alg = config_datacat[datacat]['rsmp_alg']
        self.re_bname = config_datacat[datacat]['re_bname']
        self.year = int(year)

    def work_import(self, tifnames, skelton, tag, dryrun=False):
        """Import raster data into PostGIS"""

        if 'bdt' in self.shortnames:
            print("Import of Burned Area raster is not supported by rst_import tool.  Merged shape files are created instead.")
            return


        def mkskel(skelton=skelton, tag=tag):
            tblname = '_'.join(['skel', 'rst', tag])
            dstname = schema + '.' + tblname
            drop_table = ['psql', '-c', 'DROP TABLE IF EXISTS %s;' % dstname] 
            # create table of skelton
            # scratch shape file
            tmpname = 'tmp_skel.shp'
            save_as_shp(skelton, tmpname)

            # populate table
            cmd = 'shp2pgsql -d -s 4326 -I'.split()
            cmd += [tmpname, dstname]
            #print(cmd)
            p1 = subprocess.Popen(cmd, stdout=subprocess.PIPE)
            p2 = subprocess.Popen(['psql',], stdin=p1.stdout)
            p2.communicate()

            # done
            drv = ogr.GetDriverByName('ESRI Shapefile')
            try:
                drv.DeleteDataSource(tmpname)
            except: pass


        if dryrun:
            # only save skelton file as shp
            tmpname = 'tmp_skel.shp'
            save_as_shp(skelton, tmpname)
        else:
            create_schema = ["psql", "-c", 'CREATE SCHEMA IF NOT EXISTS %s;' % schema]
            subprocess.run(create_schema, stdout=subprocess.PIPE)

            # delete skelton, if exists
            tblname = '_'.join(['skel', 'rst', tag])
            sklname = schema + '.' + tblname
            drop_table = ['psql', '-c', 'DROP TABLE IF EXISTS %s;' % sklname] 
            # delete pyramids, if exists
            for o in o_lvls:
                ovrname = schema + '.' + '_'.join(['o', str(o), 'rst', tag])
                drop_table = ['psql', '-c', 'DROP TABLE IF EXISTS %s;' % ovrname]
                subprocess.run(drop_table, stdout=subprocess.PIPE)
            # delete raster, if exists
            dstname = schema + '.' + '_'.join(['rst', tag])
            drop_table = ['psql', '-c', 'DROP TABLE IF EXISTS %s;' % dstname]
            subprocess.run(drop_table, stdout=subprocess.PIPE)

            # process tif files one by one
            # common tasks for imports
            opts_common = '-s 4326 -N 255'.split()  # srs and nodata value

            # it's better to create overview after everthing got loaded
            #opts_common += ['-l', ','.join(o_lvls)]  # some pyramids (hard to do...)

            opts_common += ['-t',  '%(tilesiz)sx%(tilesiz)s' % dict(tilesiz=tilesiz_db)]

            # options specific to first/middle/last files
            opts_first = ['-c']  # create
            opts_middle = ['-a'] # append
            opts_last = ['-a'] + '-C -I -M'.split() # constraints, and GiST index, vacuum analysis

            # run raster2pgsql, piped to psql
            for i,tif in enumerate(tifnames):
                print('%d of %d...' % (i+1, len(tifnames)))
                cmd = ['raster2pgsql']
                if i == 0:
                    cmd += opts_first
                elif i == len(tifnames)-1:
                    cmd += opts_last
                else:
                    cmd += opts_middle
                cmd += (opts_common + [tif] + [dstname])
                out = subprocess.Popen(cmd, stdout=subprocess.PIPE)
                psql = subprocess.Popen(['psql'], stdin=out.stdout,
                                        stdout=subprocess.PIPE)
                out.stdout.close()
                psql.communicate()[0]

            # create overview
            for l in o_lvls:
                cmd = ['psql', '-c']
                cmd += [ "SELECT ST_CreateOverview('%s'::regclass, 'rast', %s);" %  (dstname, l)]
                #print(cmd)
                subprocess.run(cmd)

            # make skelton table
            mkskel(skelton, tag)






    def work_merge(self, fnames, workdir, dryrun=False):
        """For each file, merge three layers into 3 band raster & import."""
        if not os.path.exists(workdir):
            os.makedirs(workdir)

        lyrnames = self.lyrnames

        buf = []

        for fname in fnames:
            rname = os.path.basename(fname)
            tifname = os.path.join(workdir, rname[:-4] + '.tif')
            sdsnames = [get_sdsname(_, fname) for _ in lyrnames]
            #tiffopt = ['-co %s' % _ for _ in tiffopts]
            tiffopt = list(itertools.chain.from_iterable(['-co', _] for _ in  tiffopts))
            #print(tiffopt)

            params = dict(
                file=tifname,
                mrg_opt = self.mrg_opt,
                opt=tiffopt ,
                sds=sdsnames,
            )

            cmd = "gdal_merge.py %(mrg_opt)s -o %(file)s %(opt)s %(sds)s" % params
            cmd = ["gdal_merge.py"]
            cmd += params['mrg_opt']
            cmd += ['-o', params['file']]
            cmd += params['opt']
            cmd += params['sds']

            if dryrun:
                pass
            else:
                cmd_x = ' '.join(cmd)
                if len(cmd_x) > 255: 
                    cmd_x = cmd_x[:255] + ' ...'
                if os.path.exists(tifname): os.remove(tifname)
                print('cmd: ' + cmd_x)
                subprocess.run(cmd, check=True)

            buf.append(tifname)
        return buf



    def work_polygonize(self, tifnames, dstdir, bname, dryrun=False):
        # create vrt first, and then generate tiled warped files
        if not os.path.exists(dstdir): os.makedirs(dstdir)

        # create vrtual dataset
        vrtname = os.path.join(dstdir, 'src.vrt')
        #cmd = 'gdalbuildvrt %s %s'  % ( vrtname, ' '.join(tifnames))
        # anaconda on win had trouble with long command line, ,so rewrote with -input_file_ist
        with open('tifnames.txt','w') as f:
            f.write('\n'.join(tifnames) + '\n')
        cmd = 'gdalbuildvrt %s -input_file_list %s'  % ( vrtname, 'tifnames.txt')
        status = os.system(cmd)
        if status != 0:
            raise RuntimeError('exit status %s, cmd = %s' % (status, cmd))

        # open the unified band
        ds = gdal.Open(vrtname)
        srs0 = ds.GetProjection()
        #print(srs0)
        #print(ds)
        b = ds.GetRasterBand(1)

        # create mask band
        # valid data are 1-366.  0 is unbunred, -1 fill, -2 water
        # mask file should has 1 for valid, 0 for invalid
        drv = gdal.GetDriverByName('MEM')
        dsm = drv.CreateCopy('mem0', ds)
        m = dsm.GetRasterBand(1)
        arr = m.ReadAsArray()
        arr[arr<0] = 0
        m.WriteArray(arr)

        oname0 = os.path.join(dstdir, '.'.join([bname, 'sinu','shp']))
        oname = os.path.join(dstdir, '.'.join([bname, 'shp']))
        #print(oname0)
        #print(oname)

        # output shapefile
        #drv = ogr.GetDriverByName('Memory')
        drv = ogr.GetDriverByName('ESRI Shapefile')
        if os.path.exists(oname0):
            drv.DeleteDataSource(oname0)
        dst0 = drv.CreateDataSource(oname0)
        srs = osr.SpatialReference()
        srs.ImportFromWkt(srs0)
        #print(dst0)
        #print(ogr)
        lyr0 = dst0.CreateLayer('lyr0', srs, ogr.wkbPolygon)
        #print(lyr0)

        fd = ogr.FieldDefn('BurnYear', ogr.OFTInteger)
        lyr0.CreateField(fd)
        fd = ogr.FieldDefn('BurnDate', ogr.OFTInteger)
        lyr0.CreateField(fd)
        fd = ogr.FieldDefn('area_sqkm', ogr.OFTReal)
        lyr0.CreateField(fd)
        fld = 1  #second field

        gdal.Polygonize(b, m, lyr0, fld, [], callback=None)
        del b, m   # band
        del ds, dsm  # raster

        lyr0.SetNextByIndex(0)
        for i,feat in enumerate(lyr0):
            feat.SetField('BurnYear', self.year)
            geom = feat.GetGeometryRef()
            feat.SetField('area_sqkm', geom.GetArea() / 1000000)

            lyr0.SetFeature(feat)


        # project
        target_projection =  '+proj=longlat +datum=WGS84 +no_defs'

        drv = ogr.GetDriverByName('ESRI Shapefile')
        if os.path.exists(oname):
            drv.DeleteDataSource(oname)
        srs1 = osr.SpatialReference()
        srs1.ImportFromProj4(target_projection)
        dst = transform_coordinates(dst0, srs1, drv, oname=oname)
        del lyr0
        del dst0

        return dst

    def work_resample_pieces(self, tifnames, dstdir, bname, hdfnames, dryrun=False):

        # create vrt first, and then generate tiled warped files
        if not os.path.exists(dstdir): os.makedirs(dstdir)



        target_projection =  '+proj=longlat +datum=WGS84 +no_defs'

        # create sketlton
        # based on tif files, create polygon(s) representing region where data is avarilble
        ds_skelton = None
        for tifname,hdfname in zip(tifnames,hdfnames):
            ds_skelton = get_skelton(tifname, ds_skelton,name_use=hdfname, fn_censor=censor_sinu)
        #save_as_shp(ds_skelton, 'skely0.shp')

        # project skelton
        srs1 = osr.SpatialReference()
        srs1.ImportFromProj4(target_projection)
        ds_skelton = transform_coordinates(ds_skelton, srs1)
        #save_as_shp(ds_skelton, 'skely1.shp')

        if 'bdt' in self.shortnames:
            dso = self.work_polygonize(tifnames, dstdir, bname, dryrun)
            return [dso], ds_skelton
        
        intersector = Intersecter(ds_skelton)

        # create vrtual dataset
        vrtname = os.path.join(dstdir, 'src.vrt')
        #cmd = 'gdalbuildvrt %s %s'  % ( vrtname, ' '.join(tifnames))
        # anaconda on win had trouble with long command line, ,so rewrote with -input_file_ist
        with open('tifnames.txt','w') as f:
            f.write('\n'.join(tifnames) + '\n')
        cmd = 'gdalbuildvrt %s -input_file_list %s'  % ( vrtname, 'tifnames.txt')
        status = os.system(cmd)
        if status != 0:
            raise RuntimeError('exit status %s, cmd = %s' % (status, cmd))

        res = '-tr 0.00166666666666666666666666666667 0.00166666666666666666666666666667'  # 6 sec
        prj = '-t_srs "%s"' % target_projection
        tiffopt = ' '.join(['-co %s' % _ for _ in tiffopts])

        onames = []

        for i in range(36):
            for j in range(18):
                c = (-180 + 10*i, 90 - 10*(j+1), -180+10*(i+1), 90-10*j)
                te = '-te %s' % ' '.join(str(_) for _ in c)
                oname = os.path.join(dstdir, '.'.join([bname, 'r%02dc%02d' % (i,
                    j), 'tif']))

                # if tile does not overlap with any skelton polygons, dont resample
                poly = Polygon([[c[0],c[1]],[c[0],c[3]],[c[2],c[3]],[c[2],c[1]],[c[0],c[1]]])
                intsct = intersector(poly)
                if intsct.IsEmpty(): continue


                cmd = ( 'gdalwarp %(prj)s %(res)s %(te)s ' + \
                        '-overwrite -r %(rsmp_alg)s -dstnodata 255 ' + \
                        '-wo INIT_DEST=NO_DATA -wo NUM_THREADS=ALL_CPUS ' + \
                        '%(tiffopt)s %(fname)s %(oname)s' ) % dict(
                            fname=vrtname, oname=oname,
                            tiffopt=tiffopt, prj=prj, res=res, te=te, rsmp_alg = self.rsmp_alg)
                if not dryrun:
                    if len(cmd) > 255: 
                        cmd_x = cmd[:255] + ' ...'
                    else:
                        cmd_x = cmd
                    print('cmd: ' + cmd_x)
                    subprocess.run(shlex.split(cmd), check=True)
                onames.append(oname)
        return onames, ds_skelton


def main(tag, fnames, workdir=None, run_merge=True, run_resample=True, run_import=True ):

    importer = Importer(fnames=fnames)
    if workdir is None:
        workdir = './proc_%s' % tag
    logfilename = 'log.%s.txt' % tag
    logfile = open(logfilename, 'w')

    bname = os.path.basename(fnames[0])
    m = importer.re_bname.match(bname)
    if not m:
        raise RuntimeError('unexpected bname: %s vs. %s' %(bname, importer.re_bname))
    bname = m.group(0)
    print('bname: ' + bname)

    # merge
    dir_merge = os.path.join(workdir, 'mrg')

    # merge bands first as files
    if run_merge:
        logfile.write('merge start : %s\n' % datetime.datetime.now().isoformat() )
        mrgnames = importer.work_merge(fnames, dir_merge, dryrun = False)
        logfile.write('merge finish: %s\n' % datetime.datetime.now().isoformat() )
    else:
        mrgnames = importer.work_merge(fnames, dir_merge, dryrun = True)

    # resample
    dir_rsmp = os.path.join(workdir, 'rsp')
    if run_resample:
        logfile.write('resmp start : %s\n' % datetime.datetime.now().isoformat() )
        rsmpnames,skelton = importer.work_resample_pieces(mrgnames, dir_rsmp, bname, fnames)
        logfile.write('resmp finish: %s\n' % datetime.datetime.now().isoformat() )
    else:
        rsmpnames,skelton = importer.work_resample_pieces(mrgnames, dir_rsmp, bname, fnames,
                dryrun=True)

    # import
    if run_import:
        logfile.write('imprt start : %s\n' % datetime.datetime.now().isoformat())
        importer.work_import(rsmpnames, skelton, tag)
        logfile.write('imprt finish: %s\n' % datetime.datetime.now().isoformat())
    else:
        importer.work_import(rsmpnames, skelton, tag, dryrun=True)


if __name__ == '__main__':
    import sys
    #tag = sys.argv[1]
    #fnames = sys.argv[2:]

    #main(tag, fnames)
    raise RuntimeError('script use not supported')
