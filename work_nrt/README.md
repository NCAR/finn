## Use without notebook

For automated executtion of code, `*.py` codes are available which does something similar to `work_generic/main_generic.ipynb` 

* work_raster.py<br />
Grab global raster for MODIS LCT and VCF and import into database

* work_nrt.py<br />
Process AF into burened area and land characterized text file, to be processed further by emission model.

* work_common.py<br />
Above two code shares some common metadata/functinalities, and they are put into here

* demo_nrt.sh<br />
How to run this tool from command line, for NRT processing.

* demo_oregin.sh<br />
Script to reproduce the Oregon test case processing, with this new interface

At this point, database that is distributed as docker container can be used.  System version of database should work with the same script too, by setting database access settings appropriately (found in work_common.py near the top, PGPORT etc).


