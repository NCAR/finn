import geopandas as gpd
import pandas as pd
import numpy as np
from pathlib import Path

def get_centroid(shpname):
    # dissolved by fireid, then reporet centroid coordinate
    df = gpd.read_file(shpname)[['fireid', 'geometry']]

    # dissolve by fireid
    ddf = df.dissolve('fireid')
    print(ddf.head())

    # get centroid coord (approx)
    c = ddf.geometry.centroid
    ddf['lon'] = c.x.astype(np.float32)
    ddf['lat'] = c.y.astype(np.float32)
    print(ddf.head())

    # return lon/lat (with fireid as index)
    ddf = ddf[['lon', 'lat']]
    return ddf

def calc_area(csvname):
    df = pd.read_csv(csvname)[['fireid', 'area_sqkm', 'f_lct', 'v_lct', 'v_tree', 'v_herb', 'v_bare']]
    df['a_tree'] = (df.area_sqkm * df.f_lct * df.v_tree).astype(np.float32)
    df['a_herb'] = (df.area_sqkm * df.f_lct * df.v_herb).astype(np.float32)
    df['a_bare'] = (df.area_sqkm * df.f_lct * df.v_bare).astype(np.float32)
    df = df[['fireid', 'v_lct', 'a_tree', 'a_herb', 'a_bare']]
    dfo = df.groupby(['fireid', 'v_lct']).sum()
    return dfo

ddir = Path('../../output_data/fire')

cases = ('native', 'docker')
shpnames= {_: ddir / f'modvrs_nrt_2020299_{_}/out_modvrs_nrt_2020299_{_}_modlct_2019_modvcf_2019_regnum.shp' for _ in cases}
csvnames = {k:v.with_suffix('.csv') for k,v in shpnames.items()}


centers = {cas:get_centroid(shpname) for cas,shpname in shpnames.items()}

### 
### for k,v in centers.items():
###     v.to_csv(f'center_{k}.csv')

areas = {cas: calc_area(csvname) for cas, csvname in csvnames.items()}

### for k,v in areas.items():
###     v.to_csv(f'area_{k}.csv', float_format='{:.2f}'.format)

import pickle
pickle.dump([centers, areas], open('stuff.pkl', 'wb'))

for cas in cases:
    dfo = centers[cas].join(areas[cas])
    for c in ('a_tree', 'a_herb', 'a_bare'):
        dfo[c] = dfo[c].map(lambda x: '{:.2f}'.format(x))
    dfo.to_csv(f'area_by_fireid_lct_vcf_{cas}.csv')




