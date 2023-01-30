import os, re
import subprocess
from subprocess import Popen

def main(odir, schema, tblname, flds, shpname=None, csvonly=False, date_definition='LST'):
    if shpname is None:
        shpname = tblnam + '.shp'

    csvname = os.path.join(odir, re.sub('.shp$' , '.csv', shpname))

    acq_date_used = "acq_date_" + date_definition.lower()

    
    # get the attribute table
    cmd = ['psql', '-c'] + [
            "\COPY (SELECT polyid,fireid,cen_lon,cen_lat,acq_date_use as {acq_date_used},area_sqkm,alg_agg,{flds} FROM \"{schema}\".\"{tblname}\") TO '{csvname}' DELIMITER ',' CSV HEADER".format(
                flds=','.join(flds),
                schema=schema,
                tblname=tblname,
                csvname=csvname,
                acq_date_used = acq_date_used,
                )
            ]
    print('exporting: %s ...' % csvname, end=' ')
    subprocess.run(cmd, check=True)
    print('Done')
#    p = Popen(cmd)
#    p.communicate()
    #subprocess

    if not csvonly:
        ## # also get as shape file, for QA
        ## ogr2ogr -f "ESRI Shapefile" global_${yr}_div.shp PG:"host=localhost dbname=finn" -sql "select * from global_${yr}.out_div;"
        #pgsql2shp -f tes -h localhost finn global_${yr}.out_div
    #    cmd = ['pgsql2shp', '-f', tblname, 'finn', '{0}.{1}'.format(schema, tblname)]
        cmd = ['ogr2ogr', '-progress', '-f', 'ESRI Shapefile', '-overwrite', os.path.join(odir, shpname), 'PG:dbname={0}'.format(os.environ['PGDATABASE']),  
                '-sql', 'select * from "{schema}"."{tblname}"'.format(schema=schema, tblname=tblname )]
        print('exporting: %s ...' % os.path.join(odir, shpname), end=' ')
        subprocess.run(cmd, check=True)
        print('Done')
        #p = Popen(cmd)
        #p.communicate()
    
