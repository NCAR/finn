#!/bin/bash


#ddir=../sample_datasets/fire/testOTS_092018
data_dir=/home/finn/input_data/fire/testOTS_092018
out_dir=/home/finn/output_data/fire/testOTS_092018


# grab  relevant raster
python3 ./work_raster.py -t testOTS_092018 -y 2017 \
	$data_dir/fire_archive_M6_23960.shp \
	$data_dir/fire_archive_V1_23961.shp


python3 ./work_nrt.py -t testOTS_092018 -y 2017 \
	-o $out_dir \
	$data_dir/fire_archive_M6_23960.shp \
	$data_dir/fire_archive_V1_23961.shp
