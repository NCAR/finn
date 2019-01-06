import os
from subprocess import Popen

def main(odir, schema, tblname, flds):

    csvname = os.path.join(odir, tblname + '.csv')

    
    # get the attribute table
    cmd = ['psql', '-c'] + [
            "\COPY (SELECT polyid,fireid,cen_lon,cen_lat,acq_date_lst,area_sqkm,{flds} FROM \"{schema}\".\"{tblname}\") TO '{csvname}' DELIMITER ',' CSV HEADER".format(
                flds=','.join(flds),
                schema=schema,
                tblname=tblname,
                csvname=csvname
                )
            ]
    p = Popen(cmd)
    p.communicate()

    ## # also get as shape file, for QA
    ## ogr2ogr -f "ESRI Shapefile" global_${yr}_div.shp PG:"host=localhost dbname=finn" -sql "select * from global_${yr}.out_div;"
    #pgsql2shp -f tes -h localhost finn global_${yr}.out_div
#    cmd = ['pgsql2shp', '-f', tblname, 'finn', '{0}.{1}'.format(schema, tblname)]
    cmd = ['ogr2ogr', '-progress', '-f', 'ESRI Shapefile', '-overwrite', '{0}.shp'.format(tblname), 'PG:dbname={0}'.format(os.environ['PGDATABASE']),  
            '-sql', 'select * from "{schema}"."{tblname}"'.format(schema=schema, tblname=tblname )]
    p = Popen(cmd)
    p.communicate()

