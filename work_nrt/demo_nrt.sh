#!/bin/bash

#data_dir=../data
tag=modvrs_nrt_2020299 
data_dir=/home/finn/input_data/fire
out_dir=/home/finn/output_data/fire/$tag

# TODO specify days of interest
# TODO die prematury, if nothing left after removing by date

# grab annual global raster (can be commented out if you know that it's already imported into the database)
python3 ./work_raster.py -y 2019


# process af
python3 ./work_nrt.py -t $tag -y 2019 \
	-o $out_dir \
       	-fd 2020299 -ld 2020299 \
	$data_dir/MODIS_C6_Global_MCD14DL_NRT_2020298.txt \
	$data_dir/MODIS_C6_Global_MCD14DL_NRT_2020299.txt \
	$data_dir/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020298.txt \
	$data_dir/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020299.txt
