#!/bin/bash
year=2016

dbname=finn
schemaname=global_$year
archname=M6_23581

src=../../downloads/firms/global_$year/fire_archive_${archname}.shp
dst=${schemaname}.af_in

psql -d finn -c "DROP SCHEMA IF EXISTS ${schemaname} CASCADE;"
psql -d finn -c "CREATE SCHEMA $schemaname;"

shp2pgsql -d -c -s 4326 -I $src $dst | psql -q -d finn > import_af.log
