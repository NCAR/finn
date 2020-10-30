# python libraries
import sys
import os
import subprocess
import re
import getpass

# TODO this should be done somewhere else?  maybe $HOME/.bashrc ? 

my_env = 'from_docker'
#my_env = 'use_docker'
#my_env = 'use_native'

print(my_env)
if my_env == 'use_docker':
    # from docker at acom-finn
    os.environ['PGDATABASE'] = 'finn'
    os.environ['PGPASSWORD'] = 'finn'
    os.environ['PGUSER'] = 'finn'
    os.environ['PGPORT'] = '25432'
    os.environ['PGHOST'] = 'localhost'
elif my_env == 'use_native':
    # native veersion on acon-finn
    os.environ['PGDATABASE'] = 'postgres'
    if 'PGPASSWORD' not in os.environ:
        os.environ['PGPASSWORD'] = getpass.getpass(prompt='PGPASSWORD? ')
    os.environ['PGUSER'] = 'postgres'
    os.environ['PGPORT'] = '5432'
    os.environ['PGHOST'] = ''
elif my_env == 'from_docker':
    # running from inside the docker, traditional use
    os.environ['PGDATABASE'] = 'finn'
    os.environ['PGPASSWORD'] = 'finn'
    os.environ['PGUSER'] = 'finn'
    os.environ['PGPORT'] = '5432'
    os.environ['PGHOST'] = 'localhost'
else:
    raise RuntimeError


if 'EARTHDATAUSER' not in os.environ:
    os.environ['EARTHDATAUSER'] = input('EARTHDATAUSER? ')
if 'EARTHDATAPW' not in os.environ:
    os.environ['EARTHDATAPW'] = getpass.getpass(prompt='EARTHDATAPW? ')

os.environ['PATH'] += os.pathsep + '/usr/pgsql-11/bin'



# finn preproc codes
sys.path = sys.path + ['../code_anaconda']

import rst_import

testinputs = {
        'tag_af': 'testOTS_092018',
        'af_fnames': [ 
            '../sample_datasets/fire/testOTS_092018/fire_archive_M6_23960.shp',
            '../sample_datasets/fire/testOTS_092018/fire_archive_V1_23961.shp',
            ], 
        'year_rst':2017,
        }


def sec1_user_config(tag_af, af_fnames, year_rst):

    # hard-wired options
    filter_persistent_sources = True

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

    # save *.shp of the output, so that you can hold onto polygons
    save_shp_of_output = True

    # save *.html version of this notebook upon exit, so that you can keep records
    save_html_of_notebook = True

    # deletes entire schema in the database for the AF data processed in this notebook
    wipe_intermediate_vector_in_db = False

    # deletes hdf files downloaded from EARTHDATA for particular year used in this notebook
    wipe_downloaded_hdf = False

    # deletes intermediate geotiff files (found in proc_rst_XXX directory) for particular year used in this notebook
    wipe_intermediate_geotiff = False

    # deletes table of raster data imported into database (praticular year used in this notebook)
    wipe_intermediate_rst_in_db = False

    return locals()


def sec2_check_environment(out):

    #out.write('\n'.join([k + '=' + os.environ[k] for  k in sorted(os.environ)]) + '\n\n')

    out.write('system environment inside docker container, for debugging purpose\n\n')
    subprocess.run(['env' , '|', 'sort'], stdout=out, shell=True)

    subprocess.run(['psql', '-c', 'select version();'], stdout = out)
    subprocess.run(['psql', '-c', 'select postgis_full_version();'], stdout = out)

    subprocess.run(['psql', '-f', '../code_anaconda/testpy.sql'], stdout = out)
    
    rst_import.prep_modis_tile()
