#!/bin/bash

# specify if docker will be used to run model
#  'use_native' = no docker, everything installed on the host system
#  'use_docker' = use postgis in docker.  some aux tool (gdal, psql, python etc) need to be installed to the system
#  'use_from_inside_docker' = use docker for everything.  to use this option, invoke this scrpt with
#    docker exec finn /home/finn/work_nrt/demo_nrt_from_inside_docker.sh
#
export FINN_DRIVER=use_docker

# use UTC to decide date, or approximate local solar time (LST)
export FINN_DATE_DEFINITION=LST

# identifier of the af dataset
tag=testOTS_092017 

# downloaded FIRMS AF data
data_dir=/home/finn/input_data/fire/$tag

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

# grab  relevant raster (it doensn't download/import if necessary raster data already exist in the database)
python3 $exc_dir/work_raster.py -t $tag -y 2016 \
	$data_dir/fire_archive_M6_23960.shp \
	$data_dir/fire_archive_V1_23961.shp

if [ $? -ne 0 ]; then
	echo problem in work_raster.py
	exit 1
fi


# process af
python3 $exc_dir/work_nrt.py -t $tag -y 2016 \
	-o $out_dir \
        -s $summary_file \
	$data_dir/fire_archive_M6_23960.shp \
	$data_dir/fire_archive_V1_23961.shp

if [ $? -ne 0 ]; then
	echo problem in work_nrt.py
	exit 2
fi

### # Purge the intermediate results in the database
### python3 $exc_dir/work_clean.py -t $tag \
### 	-s $summary_file
### 
### 
### if [ $? -ne 0 ]; then
### 	echo problem in work_clean.py
### 	exit 3
### fi

echo Done Successfully for $tag .
