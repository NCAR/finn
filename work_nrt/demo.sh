#!/bin/bash
# python3 ./work_nrt.py -t c6_nrt_2020299 -y 2019 \
# 	../data/MODIS_C6_Global_MCD14DL_NRT_2020298.txt \
# 	../data/MODIS_C6_Global_MCD14DL_NRT_2020299.txt \
# 	../data/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020298.txt \
# 	../data/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020299.txt

#python3 ./work_nrt.py -t c6_nrt_2020299 -y 2019 ../data/MODIS_C6_Global_MCD14DL_NRT_2020299.txt


python3 ./work_nrt.py -t modissuomi_nrt_2020299 -y 2019 \
	../data/MODIS_C6_Global_MCD14DL_NRT_2020298.txt \
	../data/MODIS_C6_Global_MCD14DL_NRT_2020299.txt \
	../data/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020298.txt \
	../data/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_2020299.txt
