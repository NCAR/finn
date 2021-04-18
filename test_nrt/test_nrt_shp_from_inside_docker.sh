#!/bin/bash

# run tool from inside docker, using postgis and all other tools provided in docker
export FINN_DRIVER=from_inside_docker

# use UTC to decide date, or approximate local solar time (LST)
export FINN_DATE_DEFINITION=UTC

# identifier of the af dataset
tag=modvrs_nrt_2020299_shp_from_inside_docker

# downloaded FIRMS AF data
data_dir=/home/finn/input_data/fire

# processed burned area information
out_dir=/home/finn/output_data/fire/${tag}

exc_dir=../code_bashinterface

# optionally processing summary and disk use info can be saved in a file
# remove "-s $summary_file" altogether, if you want this info to dumped to screen
summary_file=$out_dir/processing_summary_${tag}.txt

if [ x$FINN_DRIVER == xfrom_inside_docker ]; then
  # need to be sure that start processing from work_nrt dir
  here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
  cd $here
fi

### # grab annual global raster (can be commented out if you know that it's already imported into the database)
### python3 $exc_dir/work_raster.py -y 2019
### 

if [ $? -ne 0 ]; then
	echo problem in work_raster.py
	exit 1
fi


# process af
python3 $exc_dir/work_nrt.py -t $tag -y 2019 \
	-o $out_dir \
       	-fd 2020299 -ld 2020299 \
        -s $summary_file \
	$data_dir/fire_nrt_M6_10032_filtered.shp \
	$data_dir/fire_nrt_V1_10034.shp

if [ $? -ne 0 ]; then
	echo problem in work_nrt.py
	exit 2
fi

# Purge the intermediate results in the database
python3 $exc_dir/work_clean.py -t $tag \
	-s $summary_file


if [ $? -ne 0 ]; then
	echo problem in work_clean.py
	exit 3
fi

echo Done Successfully for $tag .
