#!/bin/bash
# python3 ./work_nrt.py -t c6_nrt_2020299 -y 2019 \
# 	../data/MODIS_C6_Global_MCD14DL_NRT_2020298.txt \
# 	../data/MODIS_C6_Global_MCD14DL_NRT_2020299.txt \
# 	../data/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020298.txt \
# 	../data/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020299.txt

#python3 ./work_nrt.py -t c6_nrt_2020299 -y 2019 ../data/MODIS_C6_Global_MCD14DL_NRT_2020299.txt

#ddir=../data
ddir=/home/finn/input_data/fire

# TODO specify days of interest


python3 ./work_nrt.py -t modvrs_nrt_2020299 -y 2019 \
	$ddir/MODIS_C6_Global_MCD14DL_NRT_2020298.txt \
	$ddir/MODIS_C6_Global_MCD14DL_NRT_2020299.txt \
	$ddir/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020298.txt \
	$ddir/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020299.txt
