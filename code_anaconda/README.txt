now everything starts from main*.py

main.py is example of global application
main_ots092018.py is a small example using a week period in oregon, 2017

in both cases, it perform same series of tasks

1. import modis lct raster, grabbing the files already downloaded
	uses raster2pgsql

2. import modis vcf raster, grabbing the files already downloaded
	uses raster2pgsql

3. import region number polygon, which Christine gave to me
	uses shp2pgsql

We dont have do this much so often because raster is released once a year,
region number won't be redefined

4. import active fire shape file
	uses either shp2pgsql or ogr2ogr

5. perform step1, which is to generate (subdivided) burned area polygons
	uses the static step1_prep*.sql and step1_work*.sql files

6. perform step2, which is detemine land cover of polygons
	python code dynamicly generate step2_prep*.sql and step2_work*.sql

7. export results into csv file and shp file
	uses "psql -c '\copy ...'" and pgsql2shp (i probably want to switch to
	ogr2ogr)

TODO:
organization of script/data is far from optimum.  i want to somehow separate
code directories (most *.py and static *.sql file) and work directory (have
only main.py, or something equivalent, e.g. config file), then keep everything
in work for outputs

Need to design user-interface, particularly when this move to docker
