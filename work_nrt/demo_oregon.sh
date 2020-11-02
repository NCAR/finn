#!/bin/bash

export PYTHONPATH=/home/yosuke/.local/lib/python3.6

#data_dir=../sample_datasets/fire/testOTS_092018
tag=testOTS_092017 
data_dir=/home/finn/input_data/fire/$tag
out_dir=/home/finn/output_data/fire/$tag

# TODO specify days of interest
# TODO die prematury, if nothing left after removing by date

# grab  relevant raster
python3 ./work_raster.py -t $tag -y 2016 \
	$data_dir/fire_archive_M6_23960.shp \
	$data_dir/fire_archive_V1_23961.shp


# process af
	#-fd 2017200 -ld 2017200 \
python3 ./work_nrt.py -t $tag -y 2016 \
	-o $out_dir \
	$data_dir/fire_archive_M6_23960.shp \
	$data_dir/fire_archive_V1_23961.shp
