## Use without notebook

For automated executtion of code, four `*.py` codes are available which does something similar to `work_generic/main_generic.ipynb` 

### files in this directory
* work_raster.py<br />
Grab global raster for MODIS LCT and VCF and import into database

* work_nrt.py<br />
Process AF into burened area and land characterized text file, to be processed further by emission model.

* work_clean.py<br />
Cleans up intermediate tables in the database after processing finished.
  
* work_common.py<br />
Above three code shares some common metadata/functinalities, and they are put into here
  
Following two shows example usage of the python scripts

* demo_nrt.sh<br />
How to run this tool from command line, for NRT processing.

* demo_oregon.sh<br />
Script to reproduce the Oregon test case processing, with this new interface
  
And one notebook file
* demo_ntr.ipynb<br />
Does the same thing as `demo_nrt.sh` using notebook interface.
  
### ways to configure tool with or without Docker

Three different ways to configure the database, libraries, and executables:  They are tagged as 'use_native', 'use_docker', 'from_inside_docker'.  

* 'use_naitve' option does not use Docker at all, user install everything needed to be run with natively compiled executables/libraries.

* 'use_docker' option uses database provided as Docker container, but use system installed executables/libraries to interact with the database.

* 'from_inside_docker' option does everything inside the docker.  User go into a running container with `docker exec -it finn /bin/bash`, and execute shell script from inside the container.  This option is closest to the Notebook based processing, where notebook exposes tools in the container to user, whereas 'from_inside_docker' uses interactive bash shell inside the container.

There are higher level of compatibility between 'from_inside_docker' method and the Notebook, as tools being used are identical.  'use_docker' approach also appears to generate identical output as other docker based approach even though external tools are used as needed.  'use_native' approach may exhibit minor incompatibility with other docker based approach.

`test_nrt` directory has series of runs with these options to test the compatibility of these approaches.
