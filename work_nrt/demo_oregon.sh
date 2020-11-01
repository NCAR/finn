#!/bin/bash


ddir=../sample_datasets/fire/testOTS_092018

# grab  relevant raster
python3 ./work_raster.py -t testOTS_092018 -y 2017 \
	$ddir/fire_archive_M6_23960.shp \
	$ddir/fire_archive_V1_23961.shp


python3 ./work_nrt.py -t testOTS_092018 -y 2017 \
	$ddir/fire_archive_M6_23960.shp \
	$ddir/fire_archive_V1_23961.shp
