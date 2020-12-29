#!/usr/bin/env python3

import pandas as pd
import numpy as np

from pathlib import Path


def work(fnames):

    dfs = {knd: pd.read_csv(fname) for knd,fname in fnames.items()}

    # polyid  fireid    cen_lon    cen_lat acq_date_utc  area_sqkm  v_lct     f_lct     v_tree     v_herb      v_bare  v_regnum

    cnt_fire = pd.DataFrame({knd: len(np.unique(df.fireid)) for knd, df in dfs.items()}, index=['cnt_fire'])
    print(cnt_fire)

    tot_area = pd.DataFrame({knd: sum(df.area_sqkm * df.f_lct) for knd, df in dfs.items()}, index=['total_area'])
    print(tot_area)

    results = pd.concat([cnt_fire, tot_area], axis=0)
    results.index = pd.MultiIndex.from_tuples([(_,'') for _ in results.index])
    print(results)

    area_by_vcf = { 
            'tree': {knd:sum(df.area_sqkm * df.f_lct * df.v_tree) for knd,df in dfs.items()},
            'herb': {knd:sum(df.area_sqkm * df.f_lct * df.v_herb) for knd,df in dfs.items()},
            'bare': {knd:sum(df.area_sqkm * df.f_lct * df.v_bare) for knd,df in dfs.items()},
            }

    area_by_vcf = pd.DataFrame(area_by_vcf.values(), 
            #index=area_by_vcf.keys()) 
            index=pd.MultiIndex.from_tuples([('by_vcf', _) for _ in area_by_vcf.keys()]))
    print(area_by_vcf)

    area_by_lct = pd.concat({ knd: 
        df.assign(**{'parea_sqkm': df.f_lct * df.area_sqkm}).groupby('v_lct').agg(
            {'parea_sqkm': 'sum'}) for knd,df in dfs.items()},
            axis=1)
    area_by_lct.index = pd.MultiIndex.from_tuples([('by_lct',_) for _ in area_by_lct.index])
    area_by_lct.columns = fnames.keys()
    print(area_by_lct)

    results = pd.concat([results, area_by_vcf, area_by_lct])
    return results



if __name__ == '__main__':

    ddir = Path('../../output_data/fire')

    knds = (
    'native', 
    'docker', 
    'from_inside_docker', 
    'shp_native', 
    'shp_docker', 
    'shp_from_inside_docker',
    )

    fnames = {knd : 
            ddir / f'modvrs_nrt_2020299_{knd}/out_modvrs_nrt_2020299_{knd}_modlct_2019_modvcf_2019_regnum.csv' 
            for knd in knds}
    results = work(fnames)
    results.to_csv('compare_nrt_2020299.csv')
