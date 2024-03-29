#!/usr/bin/env python3

"""run daily task of preprocess AF points to burned area"""

## python libraries
import os
import sys
import re
import subprocess
import argparse
import distutils
from pathlib import Path
import datetime
#
## finn preproc codes
sys.path = sys.path + ['../code_anaconda']
import af_import
import run_step1a as runner_step1a
import run_step1b as runner_step1b
import run_vcf as runner_vcf
import run_step2 as runner_step2
import export_shp
import run_extra


import work_common as common

this_script_name = os.path.basename(__file__)


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
            if af_fname[-4:].lower() in ('.shp', '.csv', '.txt'):
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


def sec6_process_activefire(first_day=None, last_day=None, run_step1=True, run_step2=True):
    # make sure that user pick the dates enclosed in AF files
    if any(_ is not None for _ in (first_day, last_day)):
        dates0 = af_import.get_dates('af_' + tag_af, combined=True)
        dates = dates0[:]
        if first_day is not None:
            # grab one more day for carry over
            oneday = datetime.timedelta(days=1)
            dates = [_ for _ in dates if _ >= first_day - oneday]
        if last_day is not None:
            dates = [_ for _ in dates if _ <= last_day]
        if not dates:
            raise RuntimeError(f'No first/last_day are not included in AF files, fst/lstday=[{first_day},{last_day}],af[{min(dates0)},{max(dates0)}]')

    if run_step1:
        print(f'\n{this_script_name}: Starting step1a ...\n')
        runner_step1a.main(tag_af, filter_persistent_sources = filter_persistent_sources, 
                first_day=first_day, last_day=last_day,
                date_definition=date_definition)
        print(f'\n{this_script_name}: Starting step1vcf ...\n')
        runner_vcf.main(tag_af, rasters,
                )

        print(f'\n{this_script_name}: Starting step1b ...\n')
        runner_step1b.main(tag_af, filter_persistent_sources = filter_persistent_sources, 
                first_day=first_day, last_day=last_day,
                date_definition=date_definition)
    else:
        print(f'\n{this_script_name}: Skipping step1\n')
    if run_step2:
        print(f'\n{this_script_name}: Starting step2 ...\n')
        runner_step2.main(tag_af, rasters, first_day=first_day, last_day=last_day)
    else:
        print(f'\n{this_script_name}: Skipping step2\n')


def sec7_export_output(out_dir, summary_file=None):
    shpname = 'out_{0}_{1}_{2}_{3}.shp'.format(tag_af, tag_lct, tag_vcf, tag_regnum)

    schema = 'af_' + tag_af
    tblname = 'out_{0}_{1}_{2}'.format(tag_lct, tag_vcf, tag_regnum)
    flds = ('v_lct', 'f_lct', 'v_tree', 'v_herb', 'v_bare', 'v_regnum')

    export_shp.main(out_dir, schema, tblname, flds, shpname, 
            date_definition = date_definition)
    run_extra.summarize_log(tag_af, summary_file)

    # summarize database space use by AF
    run_extra.db_use_af(tag_af, summary_file)




# TODO have '-f' option to clean the schema.  otherwise it wont overwrite or do anything and die
def main(tag_af, af_fnames, year_rst, out_dir, first_day=None, last_day=None, 
        summary_file=None, run_import=True, run_step1=True, run_step2=True):

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    out = sys.stdout

    if first_day is not None:
        first_day = datetime.datetime.strptime(str(first_day), '%Y%j').date()
    if last_day is not None:
        last_day = datetime.datetime.strptime(str(last_day), '%Y%j').date()

    print(f'\n{this_script_name}: Starting processing ...\n')

    user_config = common.sec1_user_config(tag_af, af_fnames, year_rst)
    globals().update(user_config)

    common.sec2_check_environment(out=out)

    if run_import:
        print(f'\n{this_script_name}: Starting AF import ...\n')
        sec3_import_af(out=out)
    else:
        print(f'\n{this_script_name}: Skipping AF import\n')

    sec6_process_activefire(first_day, last_day, run_step1, run_step2)

    #summary_file = (out_dir / 'processing_summary.txt').open('w')
    if summary_file:
        summary_file = Path(summary_file).open('a')

    print(f'\n{this_script_name}: Starting export ...\n')
    sec7_export_output(out_dir=out_dir, summary_file=summary_file)



if __name__ == '__main__':
    def str2bool(v):
        if isinstance(v, bool):
           return v
        if v.lower() in ('yes', 'true', 't', 'y', '1'):
            return True
        elif v.lower() in ('no', 'false', 'f', 'n', '0'):
            return False
        else:
            raise argparse.ArgumentTypeError('Boolean value expected.')



    parser = argparse.ArgumentParser(formatter_class = argparse.ArgumentDefaultsHelpFormatter)

    required_names = parser.add_argument_group('required arguments')

    required_names.add_argument('-t', '--tag_af', 
            default=None, required=True, help='tag for AF processing', type=str)

    parser.add_argument('-fd', '--first_day', 
            default=None, required=False, 
            help='first date (YYYYJJJ, local time) to output', type=int)
    parser.add_argument('-ld', '--last_day', 
            default=None, required=False, 
            help='last date (YYYYJJJ, local time) to output', type=int)

    required_names.add_argument('-y', '--year_rst', 
            default=None, required=True, help='dataset year for raster', type=int)
    required_names.add_argument('-o', '--out_dir', 
            default=None, required=True, help='output directory', type=str)

    parser.add_argument('-s', '--summary_file', 
            default=None, required=False, help='summary filename', type=str)

    parser.add_argument('--run_import', default=True, 
            help='wipes AF data and import [yes/no]', 
            type=str2bool, nargs='?', const=True)

    parser.add_argument('--run_step1', default=True, 
            help='run step1 (geometry processing) [yes/no]', 
            type=str2bool, nargs='?', const=True)
    parser.add_argument('--run_step2', default=True, 
            help='run step2 (lct/vcf identification) [yes/no]', 
            type=str2bool, nargs='?', const=True)

    parser.add_argument('af_fnames', 
            default=None, nargs='+', help='AF file name(s)', type=str)

    args = parser.parse_args()
    
    main(**vars(args))


