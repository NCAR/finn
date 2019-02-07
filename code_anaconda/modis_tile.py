import os
import datetime
import numbers
import re

import numpy as np
import ogr
import osr
from shapely.geometry import Polygon

fileloc = os.path.dirname(os.path.realpath(__file__))


lst_lct =  os.path.join(fileloc, 'lst.MCD12Q1.txt')
lst_vcf =  os.path.join(fileloc, 'lst.MOD44B.txt')

proj_wgs =  '+proj=longlat +datum=WGS84 +no_defs'
proj_sinu = '+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +a=6371007.181 +b=6371007.181  +units=m +no_defs'

nh = 36
nv = 18
r = 6371007.181

def censor_sinu(p):
    #p[1]/r is latitude in radian
    len_parallel = 2 * np.pi * r * np.cos(p[...,1]/r)
    p[..., 0] = np.where(  np.abs(p[..., 0]) > .5 * len_parallel , .5 * len_parallel * np.sign(p[..., 0]), p[...,0])
    return p

def land_tiles(tilelist = lst_lct):
    lst = []
    if os.path.exists(tilelist):
        lst = [re.sub(r'^.*\.(h..v..)\..*$', r'\1', _.strip()) for _ in open(tilelist)]
    else:
        raise RuntimeError('cannot find: %s' % tilelist)
    return lst

tiles_lct = land_tiles(lst_lct)
tiles_vcf = land_tiles(lst_vcf)

def mk_tiles():

    x = np.linspace(- np.pi * r, np.pi * r, nh + 1)
    y = np.linspace( .5 * np.pi * r, - .5 * np.pi * r, nv + 1)

    #num = 1200 # 1km
    #num = 200 # .05deg
    num = 50 # .2 deg

    dat = []

    for h in range(nh):
        # points on x axis
        x0, x1 = x[h], x[h+1]
        xp = np.linspace( x0, x1, num+1)
        for v in range(nv):
            # points on y
            y0, y1 = y[v], y[v+1]
            yp = np.linspace( y0, y1, num+1)
            
            tilename = 'h%02dv%02d' % (h, v)

            # coords along four sides
            xy = np.zeros((num*4+1,2))

            ###xy[(0*num):(1*num),0] = xp[0]
            ###xy[(0*num):(1*num),1] = yp[:-1]

            ###xy[(1*num):(2*num),0] = xp[:-1]
            ###xy[(1*num):(2*num),1] = yp[-1]

            ###xy[(2*num):(3*num),0] = xp[-1]
            ###xy[(2*num):(3*num),1] = yp[:0:-1]

            ###xy[(3*num):(4*num),0] = xp[:0:-1]
            ###xy[(3*num):(4*num),1] = yp[0]

            xy[(0*num):(1*num),0] = xp[:-1]
            xy[(0*num):(1*num),1] = yp[0]

            xy[(1*num):(2*num),0] = xp[-1]
            xy[(1*num):(2*num),1] = yp[:-1]

            xy[(2*num):(3*num),0] = xp[:0:-1]
            xy[(2*num):(3*num),1] = yp[-1]

            xy[(3*num):(4*num),0] = xp[0]
            xy[(3*num):(4*num),1] = yp[:0:-1]

            xy[(4*num),:] = (xp[0], yp[0])

            # censor points outside of defined area
            xy = censor_sinu(xy)

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
            if poly.area == 0:
                continue

            lct = 1 if tilename in tiles_lct else 0
            vcf = 1 if tilename in tiles_vcf else 0
            # store
            dat.append(
                    dict(
                        h = h, v = v,
                        tilename = tilename,
                        lct= lct,
                        vcf= vcf,
                        geom = poly,
                        )
                    )
    return dat

def mk_ds(dat, srs=None):
    drv = ogr.GetDriverByName('Memory')
    ds = drv.CreateDataSource('poly')
    lyr = ds.CreateLayer('', srs, ogr.wkbPolygon)
    for (k,v) in dat[0].items():
        if k == 'geom':
            pass
        if isinstance(v, numbers.Integral):
            lyr.CreateField(ogr.FieldDefn(k, ogr.OFTInteger))
        elif isinstance(v, numbers.Real):
            lyr.CreateField(ogr.FieldDefn(k, ogr.OFTReal))
        elif isinstance(v, datetime.date):
            lyr.CreateField(ogr.FieldDefn(k, ogr.OFTDate))
        elif isinstance(v, datetime.time):
            lyr.CreateField(ogr.FieldDefn(k, ogr.OFTTime))
        elif isinstance(v, datetime.datetime):
            lyr.CreateField(ogr.FieldDefn(k, ogr.OFTDateTime))
        else:
            fdefn = ogr.FieldDefn(k, ogr.OFTString)
            fdefn.SetWidth(255)
            lyr.CreateField(fdefn)
    defn = lyr.GetLayerDefn()

    for row in dat:
        feat = ogr.Feature(defn)
        for k,v in row.items():
            if k == 'geom':
                geom = ogr.CreateGeometryFromWkb(v.wkb)
                feat.SetGeometry(geom)
            else:
                feat.SetField(k, v)
        lyr.CreateFeature(feat)
    feat = geom = None
    lyr = None

    return ds

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
            
def transform_coordinates(ds, srs):

    # create target dataset
    drv = ds.GetDriver()
    ds1 = drv.CreateDataSource(ds.GetName())# + '_p')
    lyr0 = ds.GetLayer()
    lyr0.SetNextByIndex(0)
    lyr1 = ds1.CreateLayer('', srs, ogr.wkbPolygon)
    defn0 = lyr0.GetLayerDefn()
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

def get_ds_in_wgs():
    tiles = mk_tiles()
    srs0 = osr.SpatialReference()
    srs0.ImportFromProj4(proj_sinu)
def main(silent=False):

    tiles = mk_tiles()
    if not silent:
        print(len(tiles))

    srs0 = osr.SpatialReference()
    srs0.ImportFromProj4(proj_sinu)

    ds0 = mk_ds(tiles, srs=srs0)
    if not silent:
        print(ds0.GetLayer().GetFeatureCount())
        save_as_shp(ds0, 'tile_sinu.shp')

    srs1 = osr.SpatialReference()
    srs1.ImportFromProj4(proj_wgs)

    ds1 = transform_coordinates(ds0, srs1)
    if not silent:
        print(ds1.GetLayer().GetFeatureCount())
        save_as_shp(ds1, 'tile_wgs.shp')
    return ds1


if __name__ == '__main__':
    main()
    #print(land_tiles())

