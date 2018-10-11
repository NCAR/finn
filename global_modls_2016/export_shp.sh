#!/bin/bash
yr=2016
# get the attribute table
dst=$PWD
#psql -d finn -c "\\COPY (select polyid,fireid,cen_lon,cen_lat,acq_date,area_sqkm,lct,tree,herb,bare from global_${yr}.out_div) TO '$dst/global_${yr}_div.csv' DELIMITER ',' CSV HEADER"

## # also get as shape file, for QA
## ogr2ogr -f "ESRI Shapefile" global_${yr}_div.shp PG:"host=localhost dbname=finn" -sql "select * from global_${yr}.out_div;"
pgsql2shp -f tes -h localhost finn global_${yr}.out_div
