from collections import OrderedDict
import numpy as np
import gdal
import osr
import psycopg2
import psycopg2.sql as sql

import matplotlib as mpl
import matplotlib.pyplot as plt

# somehow this is needed for conda version of proj.  get rid of this if it is offending
import os
os.environ['PROJ_LIB'] = os.environ.get('PROJ_LIB', '/opt/conda/share/proj')
from mpl_toolkits.basemap import Basemap


def clr_to_cmap(clr, val=None):
    """create cmap for plab from gis .clr file"""
    v = np.loadtxt(clr)
    assert np.all(np.arange(v.shape[0]) == v[:,0])
    if not val is None:
        # subset the colors to match with min/max
        # numpy arr
        #mn = val.amin()
        #mx = val.amax()
        # masked arr
        mn = val.min()
        mx = val.max()
        v = v[mn:(mx+1),:]
    v = v[:,1:]
    cm = mpl.colors.ListedColormap(v  / 255)
    return cm

def getinfo(ds):
    o = OrderedDict()
    o['Driver'] = ds.GetDriver().LongName
    o['Files'] = ds.GetFileList()
    o['Size'] = (ds.RasterXSize, ds.RasterYSize)
    o['Coordinate System'] = ds.GetProjectionRef()
    gt = ds.GetGeoTransform()
    o['Origin'] = (gt[0], gt[3])
    o['Pixel Size'] = (gt[1], gt[5])
    o['Metadata'] = ds.GetMetadata()

    return o

def point_density(schema_table, conn = None):
    conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])
    cur = conn.cursor()

    # determine bbox
    cur.execute("""
    SELECT ST_Extent(geom) from %s;""" % schema_table)
    x = cur.fetchone()[0]
    print(x)

    # determine raser structure
    # count density (do thie in database as scratch table)
    pass

class Plotter(object):

    def __init__(self):

        self.conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])
        self.cur = self.conn.cursor()


    def mk_density(self, schema_table):

        x = schema_table.split('.')
        assert len(x) == 2
        schema_name, table_name = x

        # determine bbox
        self.cur.execute("""
                SELECT ST_Extent(geom) bbox FROM %s
                ;""" % schema_table)
        x = self.cur.fetchone()
        print(x)

        self.cur.execute("""
                WITH foo AS (
                SELECT ST_Extent(geom) bbox FROM %s
                )
                SELECT ST_XMin(foo.bbox), ST_YMin(foo.bbox), ST_XMax(foo.bbox), ST_YMax(foo.bbox)
                FROM foo
                ;""" % schema_table)
        x = self.cur.fetchone()
        print('x:', x)
        x = np.array(x)
        x[:2] = np.floor(x[:2])
        x[2:] = np.ceil(x[2:])
        print('x:', x)

        # determine raser structure
        # i am using 6 sec raster, and 32 256 overview
        # for now assume that o_32 resultion fits all
        d = x[2:] - x[:2]
        n = np.ceil(d * (60 * 60 / (6 ))).astype(int)
        n = np.ceil(d * (60 * 60 / (6 * 32))).astype(int)

        dx = 32*6/60/60

        # count density (do thie in database as scratch table)
        qry = """ 
        WITH foo as (
            SELECT 
            floor( ( ( ST_X(geom) ) - ( %(x0)f ) ) / %(dx)f ) idx,
            floor( ( ( %(y1)f ) - ( ST_Y(geom) ) ) / %(dx)f ) jdx
            FROM %(st)s
        )
        SELECT idx, jdx, count(*)
        FROM foo
        GROUP BY idx, jdx
        ;""" % dict(
            x0 = x[0],
            y0 = x[1],
            y1 = x[3],
            ny = n[1],
            dx = dx,
            sn = schema_name,
            st = schema_table,
            )
        self.cur.execute(qry)
        cnts = np.array(self.cur.fetchall())

        arr = np.zeros(n[::-1])
        arr[cnts[:,1].astype(int), cnts[:,0].astype(int)] = cnts[:,2]

        vsipath = '/vsimem/from_postgis'

        drv = gdal.GetDriverByName('GTiff')
        
        ds = drv.Create(vsipath, xsize = arr.shape[1], ysize = arr.shape[0],
                bands = 1    , eType = gdal.GDT_Float32)

        ds.SetGeoTransform([x[0], dx, 0, x[3]+dx, 0, -dx ])
        srs = osr.SpatialReference()
        srs.ImportFromEPSG(4326)
        ds.SetProjection(srs.ExportToWkt())
        
        b = ds.GetRasterBand(1)
        b.SetNoDataValue(0)
        b.WriteArray(arr)




        return ds

    def plot(self, schema_table, cmap=None, density=False):

        if density:
            ds = self.mk_density(schema_table)
        else:

            self.cur.execute("""
            SELECT ST_AsGDALRaster(ST_Union(rast), 'GTiff') FROM %s ;""" % (schema_table))

            vsipath = '/vsimem/from_postgis'

            gdal.FileFromMemBuffer(vsipath, bytes(self.cur.fetchone()[0]))

            ds = gdal.Open(vsipath)

        for k, v in getinfo(ds).items():
            print(k, ":", v)
        nb = ds.RasterCount
        for i in range(nb):
            b = ds.GetRasterBand(i+1)
            print(band_info(b))

        
        def read_one_band(b):
            arr = b.ReadAsArray()
            # need to flup upside down
            arr = arr[::-1]
            arr = np.ma.masked_values(arr, b.GetNoDataValue())
            return arr

        if nb == 1:
            b = ds.GetRasterBand(1)
            arr = read_one_band(b)
            if isinstance(cmap, str):
                cmap = clr_to_cmap(cmap, arr)

        elif nb == 3:
            arr = [read_one_band(ds.GetRasterBand(_+1)) for _ in range(3)]
            arr = np.dstack(arr)
            cmap = None
        else:
            raise RuntimeError('only 1 or 3 band raster suppoerted')

        info = getinfo(ds)

        plt.figure(figsize=(12,6))

        llcrnrlon=info['Origin'][0]
        urcrnrlat=info['Origin'][1]
        urcrnrlon=(info['Origin'][0]+info['Pixel Size'][0] * info['Size'][0])
        llcrnrlat=(info['Origin'][1]+info['Pixel Size'][1] * info['Size'][1])

        if urcrnrlon > 180:
            if urcrnrlon - 180 < .1 * info['Pixel Size'][0]:
                urcrnrlon = 180
            else:
                raise RuntimeError('urrcrnerlon: %s' % urcrnrlon)
        if llcrnrlat < -90:
            if llcrnrlat - 90 < abs(.1 * info['Pixel Size'][1]):
                llcrnrlat = -90
            else:
                raise RuntimeError('urrcrnerlon: %s' % llcrnrlat)
        
        m = Basemap(
                # need to flip upside down
                llcrnrlon=llcrnrlon,
                urcrnrlat=urcrnrlat,
                urcrnrlon=urcrnrlon, 
                llcrnrlat=llcrnrlat
                )
        m.drawcoastlines()
        print(arr.shape)
        m.imshow(arr,
                cmap=cmap)
        plt.show()

        

plotter = Plotter()
    



def plot(schema_table, cmap=None, point=False):
    conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])
    cur = conn.cursor()


    cur.execute("""
    SELECT ST_AsGDALRaster(ST_Union(rast), 'GTiff') FROM %s ;""" % (schema_table))

    vsipath = '/vsimem/from_postgis'

    gdal.FileFromMemBuffer(vsipath, bytes(cur.fetchone()[0]))

    ds = gdal.Open(vsipath)
    for k, v in getinfo(ds).items():
        print(k, ":", v)
    nb = ds.RasterCount
    for i in range(nb):
        b = ds.GetRasterBand(i+1)
        print(band_info(b))

    
    def read_one_band(b):
        arr = b.ReadAsArray()
        # need to flup upside down
        arr = arr[::-1]
        arr = np.ma.masked_values(arr, b.GetNoDataValue())
        return arr

    if nb == 1:
        b = ds.GetRasterBand(1)
        arr = read_one_band(b)
        if isinstance(cmap, str):
            cmap = clr_to_cmap(cmap, arr)

    elif nb == 3:
        arr = [read_one_band(ds.GetRasterBand(_+1)) for _ in range(3)]
        arr = np.dstack(arr)
        cmap = None
    else:
        raise RuntimeError('only 1 or 3 band raster suppoerted')

    info = getinfo(ds)

    plt.figure(figsize=(12,6))

    llcrnrlon=info['Origin'][0]
    urcrnrlat=info['Origin'][1]
    urcrnrlon=(info['Origin'][0]+info['Pixel Size'][0] * info['Size'][0])
    llcrnrlat=(info['Origin'][1]+info['Pixel Size'][1] * info['Size'][1])

    if urcrnrlon > 180:
        if urcrnrlon - 180 < .1 * info['Pixel Size'][0]:
            urcrnrlon = 180
        else:
            raise RuntimeError('urrcrnerlon: %s' % urcrnrlon)
    if llcrnrlat < -90:
        if llcrnrlat - 90 < abs(.1 * info['Pixel Size'][1]):
            llcrnrlat = -90
        else:
            raise RuntimeError('urrcrnerlon: %s' % llcrnrlat)
    
    m = Basemap(
            # need to flip upside down
            llcrnrlon=llcrnrlon,
            urcrnrlat=urcrnrlat,
            urcrnrlon=urcrnrlon, 
            llcrnrlat=llcrnrlat
            )
    m.drawcoastlines()
    print(arr.shape)
    m.imshow(arr,
            cmap=cmap)
    plt.show()

def band_info( band):
    ds = band.GetDataset()

    #print(getinfo(ds))
    info = OrderedDict()

    info['No Data Value'] = band.GetNoDataValue()
    info['Min'] = band.GetMinimum()
    info['Max'] = band.GetMaximum()
    info['Scale'] = band.GetScale()
    info['Unit Type'] = band.GetUnitType()
    return info




def tester():
    #proc('raster', 'o_32_rst_modlct_2017')
    proc('raster.o_32_rst_modlct_2017', cmap= '../code_anaconda/modlct.clr')
