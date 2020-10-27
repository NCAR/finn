#!/usr/bin/env python3

"""import raster by year"""

import sys
import os
from urllib.parse import urlparse
import glob

## TODO this should be done somewhere eles?  but before loading tools belose
## maybe even before this python script got called
#os.environ['PGDATABASE'] = 'finn'
#os.environ['PGPASSWORD'] = 'finn'
#os.environ['PGUSER'] = 'finn'
#os.environ['PGPORT'] = '25432'
#os.environ['PGHOST'] = 'localhost'


# finn preproc codes
sys.path = sys.path + ['../code_anaconda']
import downloader
import rst_import

import work_common as common

def sec4_download_raster(year_rst, download_global_raster=True):
    # always grab global
    if download_global_raster:
    #if True:
        results_indb = downloader.find_tiles_indb(data='POLYGON((-180 89,-180 -89,180 -89,180 89,-180 89))', 
                                                 knd='wkt')#, tag_lct=tag_lct, tag_vcf=tag_vcf)
    else:
        results_indb = downloader.find_tiles_indb(data='"af_%s"' % tag_af, 
                                                  knd='schema', tag_lct=tag_lct, tag_vcf=tag_vcf)
    print(results_indb)
    print()


    if results_indb['n_need'] == 0:
        print('All fire are is conained in raster')
        print('no need to download/import raster dataset')
        need_to_import_lct = False
        need_to_import_vcf = False
    else:
        print('Some fire are not conained in raster')
        print('Will download/import raster dataset')
        need_to_import_lct = (len(results_indb['tiles_missing_lct']) > 0)
        need_to_import_vcf = (len(results_indb['tiles_missing_vcf']) > 0)
        tiles_required_lct = results_indb['tiles_required_lct']
        tiles_required_vcf = results_indb['tiles_required_vcf']

    print()
    need_to_import_regnum = not downloader.find_table_indb('raster', 'rst_%s' % tag_regnum)
    if need_to_import_regnum:
        print('Region definiton shapefile will be imported')
    else:
        print('no need to import Region definiton shapefile')

    # all raster downloads are stored in following dir
    download_rootdir = '../downloads'

    # earthdata's URL for landcover and VCF
    is_leap = (year_rst % 4 == 0)
    url_lct = 'https://e4ftl01.cr.usgs.gov/MOTA/MCD12Q1.006/%d.01.01/' % year_rst
    url_vcf = 'https://e4ftl01.cr.usgs.gov/MOLT/MOD44B.006/%d.03.%02d/' % (year_rst, 5 if is_leap else 6)

    ddir_lct = download_rootdir +'/'+ ''.join(urlparse(url_lct)[1:3])
    ddir_vcf = download_rootdir +'/'+ ''.join(urlparse(url_vcf)[1:3])

    if any((need_to_import_lct, need_to_import_vcf)):
        print('LCT downloads goes to %s' % ddir_lct)
        print('VCF downloads goes to %s' % ddir_vcf)

    print(url_lct)
    print(tiles_required_lct)
    if need_to_import_lct:
        downloader.download_only_needed(url = url_lct, droot = download_rootdir, tiles=tiles_required_lct)
        downloader.purge_corrupted(ddir = ddir_lct, url=url_lct)

    if need_to_import_vcf: 
        downloader.download_only_needed(url = url_vcf, droot = download_rootdir, tiles=tiles_required_vcf)
        downloader.purge_corrupted(ddir_vcf, url=url_vcf)

    return {
            'need_to_import_lct': need_to_import_lct,
            'need_to_import_vcf': need_to_import_vcf,
            'need_to_import_regnum': need_to_import_regnum,
            'ddir_lct': ddir_lct,
            }

def sec5_import_raster(year_rst, raster_tasks):

    need_to_import_lct = raster_tasks['need_to_import_lct']
    need_to_import_vcf = raster_tasks['need_to_import_vcf']
    need_to_import_regnum = raster_tasks['need_to_import_regnum']
    ddir_lct = raster_tasks['ddir_lct']

    workdir_lct = '../proc_rst_%s' % tag_lct
    workdir_vcf = '../proc_rst_%s' % tag_vcf
    workdir_regnum = '../proc_rst_%s' % tag_regnum

    if need_to_import_lct: 
        print('LCT preprocessing occurs in %s' % workdir_lct) 
    if need_to_import_vcf: 
        print('VCF preprocessing occurs in %s' % workdir_vcf) 
    if need_to_import_regnum: 
        print('RegNum preprocessing occurs in %s' % workdir_regnum)

    if need_to_import_lct: 
        search_string = "%(ddir_lct)s/MCD12Q1.A%(year_rst)s001.h??v??.006.*.hdf" % dict(
                ddir_lct = ddir_lct, year_rst=year_rst) 
        fnames_lct = sorted(glob.glob(search_string)) 
        print('found %d hdf files' % len(fnames_lct) ) 
        if len(fnames_lct) == 0: 
            raise RuntimeError("check if downloads are successful and search string to be correct: %s" % 
                    search_string)
        rst_import.main(tag_lct, fnames=fnames_lct, workdir = workdir_lct)

    if need_to_import_vcf: 
        # grab hdf file names 
        search_string = "%(ddir_vcf)s/MOD44B.A%(year)s065.h??v??.006.*.hdf" % dict( 
                ddir_vcf = ddir_vcf, year=year_rst) 
        fnames_vcf = sorted(glob.glob(search_string)) 
        print('found %d hdf files' % len(fnames_vcf) ) 
        if len(fnames_vcf) == 0: 
            raise RuntimeError("check if downloads are successfull and search string to be correct: %s" % 
                    search_string)
        rst_import.main(tag_vcf, fnames=fnames_vcf, workdir = workdir_vcf)

    if need_to_import_regnum: 
        if not os.path.exists(os.path.join(workdir_regnum, 'All_Countries.shp')): 
            subprocess.run(['wget', '-P', workdir_regnum, 
                'https://s3-us-west-2.amazonaws.com/earthlab-finn/All_Countries.zip'], 
                check=True) 
            subprocess.run(['unzip', os.path.join(workdir_regnum, 'All_Countries.zip'), '-d' , 
                workdir_regnum ], check=True)
            polygon_import.main(tag_regnum, shpname = os.path.join(workdir_regnum, 'All_Countries.shp'))

def main(year_rst=2019):

    tag_af = common.testinputs['tag_af']
    af_fnames = common.testinputs['af_fnames']
    # only for dev
    year_rst = common.testinputs['year_rst']

    out = sys.stdout

    user_config = common.sec1_user_config(tag_af, af_fnames, year_rst)
    globals().update(user_config)

    common.sec2_check_environment(out=out)

    raster_tasks = sec4_download_raster(year_rst, download_global_raster=False)
    sec5_import_raster(year_rst, raster_tasks)

if __name__ == '__main__':
    main()

