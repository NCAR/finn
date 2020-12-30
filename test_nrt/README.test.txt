prerequisite:

as work_nrt got too much clutter, i moved all the test script to here.
i made symlink to work_*.py in work_nrt directory, since they need to be in
the same dir as script.  


approaches:

task 1)

to confrim reproducibility across different ways to process NRT data, i ran total of 6 runs with same data

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

task 2)

There are two more runs to compare this new, no-notebook interface against
traditional notebook approach.

../work/generic/main_gneric.py
test_oregon.sh

top one is conerted from main_generic.ipynb
bottom one is using new no-notebook interface.  it uses "from_inside_docker"
option to make it close to notebook based processing, plus using LST for
defining date (to be compatible with the notebook)

top one generates output in the same dir as python code (as it was for
notebook).  Secondone generates ouput to
finn-preprocessor/ouptut_data/fire/testOTS_092018
(the standard location for "from_inside_docker" approach

in addition to files generated for testing, there is archived output in 
../work_generic/sample_output.  

so comparisons are

../work_generic/sample_output/out*.csv
../work_generic/out*.csv
../ouptut_data/fire/testOTS_092018/out*.csv



results:
test_compare_results.py gather the results and very basic comparison of
outputs
- count of fire polygons (before split)
- total area of polygons
- area of polygons partition to three VCF vegetation types (km2 for tree
  covered area burned, etc)
- area of polygons partitioned acros  LCT

for the task 2) comparison (oregon case), three results mathes completely.
Therefore, new, no-notebook processing would produce the traditional approach
when everything else are identical

for the task 1)
virtually identical for 4 cases using docker.  two runs not using docker
differs somewhat from the rest of runs.  only difference between this "native"
run and "docker" run is that PostgreSQL.  it seems like versio of GDAL that
came with postgis are rather differnt:  native version uses v3.0, docker
version uses v2.4. 


Both count and area of fire are identical for all cases, it only differ by
assignment of LCT and VCF.  it mostly match by 4 digits	and order of 0.1km2,
by comparing global area burned by LCT, partitioned into three vegetation
types (tree/herb/bare).  

test_compare_output.py calculates these differences.

I further compare by fireid.  I can say that a lot of time they come out
identical.  I think I should let it go, there may be some undefined behavior
in the algorithm.  I hope the level of uncertainty is a lot smaller than
earlier ersion of finn and is practically negligible

