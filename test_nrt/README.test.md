To confirm reproducibility, I ran total of 6 runs with same data

Using identical `*.txt file` for NRT, I ran these three:

* `test_nrt_native.sh`
* `test_nrt_docker.sh`
* `test_nrt_from_inside_docker.sh`

I also downloaded shapefile for the same two days and run scripts below.
Somehow shapefile had more records than txt file above.  So 
I made _filtered version of input using `test_filter_inputs.py`, which filters shapefile 
to have identical records as .txt file has.

* `test_nrt_shp_docker.sh`
* `test_nrt_shp_from_inside_docker.sh`
* `test_nrt_shp_native.sh`

Lastly, notebook was copied from work_generic.ipynb, made it into py file 


**Note:**  
In order to run `_native` and `_docker` version of script, 
Four python script `../work_nrt/work_*.py` needs to be copied or symlinked to this directory.
