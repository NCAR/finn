#!/usr/bin/env python3

import pandas as pd
import numpy as np

from pathlib import Path

ddir = Path('../../output_data/fire')

knds = (
'native', 
'docker', 
'from_inside_docker', 
'shp_native', 
'shp_docker', 
'shp_from_inside_docker',
)


dfs = {
        knd : pd.read_csv(ddir / f'modvrs_nrt_2020299_{knd}/out_modvrs_nrt_2020299_{knd}_modlct_2019_modvcf_2019_regnum.csv') 
        for knd in knds}
# polyid  fireid    cen_lon    cen_lat acq_date_utc  area_sqkm  v_lct     f_lct     v_tree     v_herb      v_bare  v_regnum
cnt_fire = {knd: len(np.unique(df.fireid)) for knd, df in dfs.items()}
print(cnt_fire)
tot_area = {knd: sum(df.area_sqkm * df.f_lct) for knd, df in dfs.items()}
print(tot_area)
area_by_lct = { knd: df.assign(**{'parea_sqkm': df.f_lct * df.area_sqkm}).groupby('v_lct').agg({'parea_sqkm': 'sum'}) 
        for knd,df in dfs.items()}
print(area_by_lct)
