to confrim reproducibility, i ran total of 6 runs with same data

using identical *.txt file for NRT, i ran these three:

test_nrt_native.sh
test_nrt_docker.sh
test_nrt_from_inside_docker.sh

i also downloaded shp file for the same two days and run below
but somehow shp file had more record than txt file above.  so 
i made _filtered version (using test_filter_inputs.py), which filters shp
file to have identical records as .txt file

test_nrt_shp_docker.sh
test_nrt_shp_from_inside_docker.sh
test_nrt_shp_native.sh

