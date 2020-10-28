#!/usr/bin/env python3

"""run daily task of preprocess AF points to burned area"""

## python libraries
import os
import sys
#import psycopg2
import re
import subprocess
import argparse
#
## TODO this should be done somewhere eles?  but before loading tools belose
## maybe even before this python script got called
#os.environ['PGDATABASE'] = 'finn'
#os.environ['PGPASSWORD'] = 'finn'
#os.environ['PGUSER'] = 'finn'
#os.environ['PGPORT'] = '25432'
#os.environ['PGHOST'] = 'localhost'
#
## finn preproc codes
sys.path = sys.path + ['../code_anaconda']
import af_import
import run_step1
import run_step2
import export_shp
import run_extra



import work_common as common


#def sec1_user_config(tag_af, af_fnames, year_rst):
#
#    # tag to identify datasets, automatically set to be modlct_YYYY, modvcf_YYYY
#    tag_lct = 'modlct_%d' % year_rst
#    tag_vcf = 'modvcf_%d' % year_rst
#
#    # tag for the region number polygon
#    tag_regnum = 'regnum'
#
#    # definition of variables in the raster files
#    rasters = [ 
#        { 
#            'tag': tag_lct, 
#            'kind': 'thematic', 
#            'variable': 'lct' 
#            }, 
#        { 
#            'tag': tag_vcf, 
#            'kind': 'continuous', 
#            'variables': ['tree', 'herb', 'bare'], 
#            }, 
#        { 
#            'tag': tag_regnum, 
#            'kind': 'polygons', 
#            'variable_in': 'region_num', 
#            'variable': 'regnum', 
#            }, 
#        ]
#
#    # save *.shp of the output, so that you can hold onto polygons
#    save_shp_of_output = True
#
#    # save *.html version of this notebook upon exit, so that you can keep records
#    save_html_of_notebook = True
#
#    # deletes entire schema in the database for the AF data processed in this notebook
#    wipe_intermediate_vector_in_db = False
#
#    # deletes hdf files downloaded from EARTHDATA for particular year used in this notebook
#    wipe_downloaded_hdf = False
#
#    # deletes intermediate geotiff files (found in proc_rst_XXX directory) for particular year used in this notebook
#    wipe_intermediate_geotiff = False
#
#    # deletes table of raster data imported into database (praticular year used in this notebook)
#    wipe_intermediate_rst_in_db = False
#
#    return locals()
#
#
#def sec2_check_environment(out):
#
#    #out.write('\n'.join([k + '=' + os.environ[k] for  k in sorted(os.environ)]) + '\n\n')
#
#    out.write('system environment inside docker container, for debugging purpose\n\n')
#    subprocess.run(['env' , '|', 'sort'], stdout=out, shell=True)
#
#    subprocess.run(['psql', '-c', 'select version();'], stdout = out)
#    subprocess.run(['psql', '-c', 'select postgis_full_version();'], stdout = out)
#
#    subprocess.run(['psql', '-f', '../code_anaconda/testpy.sql'], stdout = out)
#    

def sec3_import_af(out):
    # check input file exists
    print('checking if input files exist:')
    re_shp = re.compile('fire_archive_(.*).shp')
    re_zip = re.compile('DL_FIRE_(.*).shp')
    re_shp_nrt = re.compile('(MODIS_C6|VNP14IMGTDL_NRT)_(.*).shp')


    for i,af_fname in enumerate(af_fnames):
        print("%s: " % af_fname, end='')
        
        pn,fn = os.path.split(af_fname)
        zname = None
        
        if os.path.exists(af_fname):
            print("exists.")
            # if .zip file, need to expand.
            if af_fname[-4:] == '.shp':
                # you are good
                print('OK')
            
            elif af_fname[-4:] == '.zip':
                # still need to unzip
                zname = af_fname
                m = re_zip.match(af_fname)
                if m:
                    arcname = m.group()[0]
                    sname = 'fire_archive_%s.shp' % arcname
                else:
                    # i cannot predict name of shp file...
                    import zipfile
                    # find what shp file included...?
                    raise RuntileError('specify .shp file in af_names list!')
                    arcname,sname = None, None
            else:
                raise RuntimeError('specify .shp file in af_names list!')
        else:
            print("doesn't exist.")
            
            if af_fname[-4:] == '.shp':
                # guess the zip file name
                
                pn,fn=os.path.split(af_fname)
                
                # see if it's the sample giant archive we provide 
                if fn == 'fire_archive_M6_28864.shp':
                    zurl = 'https://s3-us-west-2.amazonaws.com/earthlab-finn/2016-global-DL_FIRE_M6_28864.zip'
                    zn = '2016-global-DL_FIRE_M6_28864.zip'
                    zname = os.path.join(pn, zn)
                    sname = fn
                    if not os.path.exists(zname):
                        print('downloading the sample AF file: %s' % zn)
                        subprocess.run(['wget', '-P', pn, zurl], check=True)
                else:

                    # see if it's an archive of AF
                    m = re_shp.match(fn)
                    if m:
                        arcname = m.groups()[0]
                        zname = os.path.join( pn, 'DL_FIRE_%s.zip' % arcname)
                        sname = fn
                        print('  found zip: %s' % zname)
                    else:
                        # see if it's NRT data
                        m = re_shp_nrt.match(fn)

                        if m:
                            # NRT downloads
                            zname = af_fname[:-4] + '.zip'
                            sname = fn
                            print('  found zip: %s' % zname)


                        else:
                            raise RuntimeError('cannot find file: %s' % af_fname)
            else:
                raise RuntimeError('cannot find file: %s' % af_fname)
        if zname:
            print('unzipping: %s' % zname)
            subprocess.run(['unzip', '-uo', zname, '-d', os.path.dirname(zname)],
                          check=True)
            assert os.path.exists(os.path.join(pn, sname))
            af_fnames[i] = os.path.join(pn, sname)
            print('OK: done')

            
    # TODO this is destructive need to safe guard!
    # tell user schema is there, list table names and # of row of each.  Ask her to delete manually or something to proceed
    af_import.main(tag_af, af_fnames)

    print()
    for i,fn in enumerate(af_fnames):
        print(fn)
        tblname = '"af_%s".af_in_%d' % (tag_af, i+1)
        p = subprocess.run(['psql', '-c', 'select count(*) from %s;' % tblname], stdout=subprocess.PIPE)
        print(p.stdout.decode())


def sec6_process_activefire():
    run_step1.main(tag_af, filter_persistent_sources = filter_persistent_sources)
    run_step2.main(tag_af, rasters)

def sec7_export_output():
    outdir = '.'
    shpname = 'out_{0}_{1}_{2}_{3}.shp'.format(tag_af, tag_lct, tag_vcf, tag_regnum)

    schema = 'af_' + tag_af
    tblname = 'out_{0}_{1}_{2}'.format(tag_lct, tag_vcf, tag_regnum)
    flds = ('v_lct', 'f_lct', 'v_tree', 'v_herb', 'v_bare', 'v_regnum')

    export_shp.main(outdir, schema, tblname, flds, shpname)
    run_extra.summarize_log(tag_af)


# TODO get rid of default values
# TODO have '-f' option to clean the schema.  otherwise it wont overwrite or do anything and die
def main(tag_af=None, af_fnames=None, year_rst=None):

    if all([tag_af is None, af_fnames is None, year_rst==None]): 
        tag_af = common.testinputs['tag_af']
        af_fnames = common.testinputs['af_fnames']
        year_rst = common.testinputs['year_rst']


    out = sys.stdout

    user_config = common.sec1_user_config(tag_af, af_fnames, year_rst)
    globals().update(user_config)

    common.sec2_check_environment(out=out)

    sec3_import_af(out=out)

    sec6_process_activefire()

    sec7_export_output()


if __name__ == '__main__':

    parser = argparse.ArgumentParser(formatter_class = argparse.ArgumentDefaultsHelpFormatter)

    required_named = parser.add_argument_group('required arguments')

    required_named.add_argument('-t', '--tag_af', 
            default=None, required=True, help='tag for AF processing', type=str)
    required_named.add_argument('-y', '--year_rst', 
            default=None, required=True, help='dataset year for raster', type=int)
    parser.add_argument('af_fnames', 
            default=None, nargs='+', help='AF file name(s)', type=str)

    args = parser.parse_args()

    
    main(**vars(args))

