import geopandas as gpd
import pandas as pd
from pathlib import Path

ddir = Path('../../../finn/input_data/fire')
shpfiles = {
    'm': 'fire_nrt_M6_10032.shp', 'v': 'fire_nrt_V1_10034.shp', }

txtfiles = {
    'm': [
        'MODIS_C6_Global_MCD14DL_NRT_2020298.vrt',
        'MODIS_C6_Global_MCD14DL_NRT_2020299.vrt',
    ],
    'v': [
        'SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020298.vrt',
        'SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020299.vrt',
    ]}

df_shp = {k: gpd.read_file(ddir / fname) for k, fname in shpfiles.items()}
df_txt = {k: [gpd.read_file((ddir / 'tmp' / fname).with_suffix('.shp')) for fname in fnames] for k, fnames in
          txtfiles.items()}
df_txt = {k: pd.concat(v).pipe(gpd.GeoDataFrame) for k, v in df_txt.items()}

for v in df_shp.values():
    v.insert('serno', 0, v.index)

on = {'m': ['longitude', 'latitude', 'brightness', 'frp'],
      'v': ['longitude', 'latitude', 'bright_ti4', 'bright_ti5', 'frp'],
      }

df_txt = {k: v.set_index(on[k]) for k, v in df_txt.items()}
for v in df_txt.values():
    v.index.names = [_.upper() for _ in v.index.names]

df_shp = {k: v.set_index([_.upper() for _ in on[k]]) for k, v in df_shp.items()}

# df_mrg = {k:
#        df_txt[k].merge(df_shp[k], left_on = on[k], right_on = [_.upper() for _ in on[k]]) for k in ('m', 'v')}
df_mrg = {k: df_txt[k].join(df_shp[k], lsuffix='_t') for k in ('m', 'v')}

df_out = {k: df_shp[k][df_shp[k].index.isin(df_mrg[k].index)] for k in ('m', 'v')}

for k in ('m', 'v'):
    df_out[k].to_file(ddir / (shpfiles[k][:-4] + '_filtered.shp'))
