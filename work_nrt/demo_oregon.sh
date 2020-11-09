#!/bin/bash

# identifier of the af dataset
tag=testOTS_092017 

# downloaded FIRMS AF data
data_dir=/home/finn/input_data/fire/$tag

# processed burned area information
out_dir=/home/finn/output_data/fire/$tag

# optionally processing summary and disk use info can be saved in a file
# remove "-s $summary_file" altogether, if you want this info to dumped to screen
summary_file=$out_dir/processing_summary.txt
if [ -f $summary_file ]; then
	rm -f $summary_file
fi

# grab  relevant raster (it doensn't download/import if necessary raster data already exist in the database)
python3 ./work_raster.py -t $tag -y 2016 \
	$data_dir/fire_archive_M6_23960.shp \
	$data_dir/fire_archive_V1_23961.shp

if [ $? -ne 0 ]; then
	echo problem in work_raster.py
	exit 1
fi


# process af
python3 ./work_nrt.py -t $tag -y 2016 \
	-o $out_dir \
        -s $summary_file \
	$data_dir/fire_archive_M6_23960.shp \
	$data_dir/fire_archive_V1_23961.shp

if [ $? -ne 0 ]; then
	echo problem in work_nrt.py
	exit 2
fi

# Purge the intermediate results in the database
python3 work_clean.py -t $tag \
	-s $summary_file


if [ $? -ne 0 ]; then
	echo problem in work_clean.py
	exit 3
fi

echo Done Successfully for $tag .
