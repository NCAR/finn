import glob, os, datetime

os.environ['PGDATABASE'] = 'finn'
os.environ['PGUSER'] = 'postgres'
os.environ['PGPASSWORD'] = 'finn'

year = 2017
year_rst = 2016
# import lct

# tag to identify dataset
tag_lct = 'modlct_%d' % year_rst

if False:
    # source dir
    ddir = '../../downloads/e4ftl01.cr.usgs.gov/MOTA/MCD12Q1.006'

    # grab hdf file names
    fnames = sorted(glob.glob("%(ddir)s/%(year)s.01.01/MCD12Q1.A%(year)s001.h??v??.006.*.hdf" % dict(
            ddir = ddir, year=year)))
    print( 'found %d hdf files:' % len(fnames) )

    import rst_import_lct
    rst_import_lct.main(tag_lct, fnames)

    
# import vcf

# tag to identify dataset
tag_vcf = 'modvcf_%d' % year_rst

if False:
    # source dir
    ddir = '../../downloads/e4ftl01.cr.usgs.gov/MOLT/MOD44B.006'

    # grab hdf file names
    fnames = sorted(glob.glob("%(ddir)s/%(year)s.03.0[56]/MOD44B.A%(year)s065.h??v??.006.*.hdf" % dict(
            ddir = ddir, year=year)))
    print( 'found %d hdf files:' % len(fnames) )

    import rst_import_vcf
    rst_import_vcf.main(tag_vcf, fnames)

# import regnum
tag_regnum = 'regnum'
if True:
    # source dir
    ddir = '../../../rasters4Yo'

    fname = os.path.join(ddir, 'All_Countries.shp')

    import polygon_import
    polygon_import.main(fname, tag_regnum, )

# import af

# tag to identify dataset

tag_af = 'mod_ots201809_v7m'
#tag_af = 'vrs_ots201809_v7m'
#tag_af = 'modvrs_ots201809_v7m'

dt0 = datetime.date(year,7,14)
dt1 = datetime.date(year,7,22)

if True:
    # source dir
    ddir = '../../downloads/Test_Points/testOTS_092018'

    # shp file names
    arcnames = ['M6_23960',]
    #arcnames = ['V1_23961', ]
    #arcnames = ['M6_23960', 'V1_23961']
    #fname = os.path.join(ddir, 'DL_FIRE_%s' % arcname, 'fire_archive_%s.shp' % arcname)
    fnames = [os.path.join(ddir, 'DL_FIRE_%s' % _, 'fire_archive_%s.shp' % _ ) for _ in arcnames]

    import af_import
    af_import.main(tag_af, fnames)

# process af into (sudivided) burned area
if True:
    import run_step1
    run_step1.main(tag_af, dt0, dt1, ver='v7m')

if True:
    import run_step2
    assert run_step2.ver == 'v8b'
    rasters = [
            {'tag': tag_lct, 
                'kind': 'thematic',
                'variable': 'lct'},
            {'tag': tag_vcf, 
                'kind': 'continuous',
                'variables': ['tree', 'herb', 'bare'],
                },
            {'tag': tag_regnum,
                'kind': 'polygons',
                'variable_in': 'region_num',
                'variable': 'regnum',
                }

            ]
    run_step2.main(tag_af, rasters, dt0, dt1)

if True:
    import export_shp
    odir = '.'
    schema = 'af_' + tag_af
    tblname = 'out_{0}_{1}_{2}'.format(tag_lct, tag_vcf, tag_regnum)
    flds = ('v_lct', 'f_lct', 'v_tree', 'v_herb', 'v_bare', 'v_regnum')
    export_shp.main(odir, schema, tblname, flds)

