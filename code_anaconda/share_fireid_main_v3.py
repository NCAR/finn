
import share_fireid_work_v3 as shf
import psycopg2

import os

tag0 = 'global_modvrs_2018'

tag = 'global_modvrs_2018_no_lrg_poly'
year_rst = 2017

schema0 = f'af_{tag0}'
schema = f'af_{tag}'
# tag to identify datasets, automatically set to be modlct_YYYY, modvcf_YYYY
tag_lct = 'modlct_%d' % year_rst
tag_vcf = 'modvcf_%d' % year_rst

# tag for the region number polygon
tag_regnum = 'regnum'

# definition of variables in the raster files
rasters = [
        {
            'tag': tag_lct,
            'kind': 'thematic',
            'variable': 'lct'
        },
        {
            'tag': tag_vcf,
            'kind': 'continuous',
            'variables': ['tree', 'herb', 'bare'],
        },
        {
            'tag': tag_regnum,
            'kind': 'polygons',
            'variable_in': 'region_num',
            'variable': 'regnum',
        },
]
tag_rasters = '_'.join([rst['tag'] for rst in rasters])
tblname = f"out_{tag_rasters}"

shf.work(schema0, schema, tblname)
