from collections import OrderedDict
import numpy as np
import gdal
import psycopg2

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


def plot(schema_table, cmap=None):
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
