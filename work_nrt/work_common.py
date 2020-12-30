# python libraries
import sys
import os
import subprocess
import re
import getpass

# TODO this should be done somewhere else?  maybe $HOME/.bashrc ? 

# three ways to run finn preprocessor:
#
# 'use_native':  postgresql installed on the machine, along with all other tools
# (eg python, gdal tools, psql )to run preprocessor.  no docker involved
#
# 'use_docker':  use postgresql provided by docker, but everything else, use
# the system installed tools.  start docker container (docker run or start)
# and run the script from the machine
#
# 'from_inside_docker': this runs everythin inside docker, similar to the
# standard way to run finn preprocessor.  The only difference is not to use
# the jupytor notebook, but uses bash inside the docker.


# default is use_native, or specified by user in environmen variable FINN_DRIVER
my_env = os.environ.get('FINN_DRIVER', 'use_native')

my_date_definition = os.environ.get('FINN_DATE_DEFINITION', 'UTC')


print(my_env)

# thee port, dirnames are what's on ACOM@NCAR's machine, and you'd need to
# fine tune how things are set up on your machine

if my_env == 'use_native':
    # native veersion on acon-finn
    os.environ['PGDATABASE'] = 'finn'
    os.environ['PGPASSWORD'] = 'finn'
    os.environ['PGUSER'] = 'finn'
    os.environ['PGPORT'] = '5432'
    os.environ['PGHOST'] = ''

    # all raster downloads are stored in following dir
    raster_download_rootdir = '/home/finn/input_data/raster'

elif my_env == 'use_docker':
    # from docker at acom-finn
    os.environ['PGDATABASE'] = 'finn'
    os.environ['PGPASSWORD'] = 'finn'
    os.environ['PGUSER'] = 'finn'
    os.environ['PGPORT'] = '25432'  # in `docer run` i mapped port 5432 to 25432
    os.environ['PGHOST'] = 'localhost'

    # all raster downloads are stored in following dir
    raster_download_rootdir = '/home/finn/input_data/raster'

elif my_env == 'from_inside_docker':
    # running from inside the docker, traditional use
    # this works, but since volumes are mapped, path in the hoschine do not be the same from inside the docker (just like any
    # disk sharing)
    os.environ['PGDATABASE'] = 'finn'
    os.environ['PGPASSWORD'] = 'finn'
    os.environ['PGUSER'] = 'finn'
    os.environ['PGPORT'] = '5432'
    os.environ['PGHOST'] = 'localhost'

    # all raster downloads are stored in following dir
    raster_download_rootdir = '../downloads'  # this is relative to `work_nrt` dir

else:
    raise RuntimeError(f'Unknwon FINN_DEIVER: {FINN_DRIVER}')


# user should put thse into .bashrc, i'd think.  for example
# export EARTHDATAUSER=yosuke
if 'EARTHDATAUSER' not in os.environ:
    os.environ['EARTHDATAUSER'] = input('EARTHDATAUSER? ')
if 'EARTHDATAPW' not in os.environ:
    os.environ['EARTHDATAPW'] = getpass.getpass(prompt='EARTHDATAPW? ')

os.environ['PATH'] += os.pathsep + '/usr/pgsql-11/bin'

# finn preproc codes
sys.path = sys.path + ['../code_anaconda']

import rst_import


def sec1_user_config(tag_af, af_fnames, year_rst):
    """ hard-wired options"""


    # if available, use the AF's flag to tliminate persistence thermal anomaly (anthropogenic, and volcanic)
    # i think the flag is availabel on ly for archve version of product, not NRT
    # for for NRT, this flag has no effect
    filter_persistent_sources = True

    # specify if date is defined using approximate local solar time (LST) or coordinated universal time (UTC)
    # LST is defined by adding integer # of hours to UTC, 24 * longitude / 360
    #date_definition = 'UTC'  
    date_definition = my_date_definition


    # tag to identify datasets, automatically set to be modlct_YYYY, modvcf_YYYY
    #tag_lct = 'modlct_%d' % year_rst
    #tag_vcf = 'modvcf_%d' % year_rst
    tag_lct = 'modlct_%s' % year_rst
    tag_vcf = 'modvcf_%s' % year_rst

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
