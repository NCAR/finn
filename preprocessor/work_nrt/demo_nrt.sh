#!/bin/bash

# date to process
date=2023-03-01

# date to prcess in julian format
yj=$(date -d $date +'%Y%j')

# year, and a year ago
yr=$( date -d $date +'%Y')
#yrm1=$(( $yr - 1 ))
yrm2=$(( $yr - 2 ))

yjm1=$(date -d "$date -1 day" +'%Y%j')


# specify if docker will be used to run model
#  'use_native' = no docker, everything installed on the host system
#  'use_docker' = use postgis in docker.  some aux tool (gdal, psql, python etc) need to be installed to the system
#  'use_from_inside_docker' = use docker for everything.  to use this option, invoke this scrpt with
#    docker exec finn /home/finn/work_nrt/demo_nrt_from_inside_docker.sh
#
export FINN_DRIVER=use_native

# use UTC to decide date, or approximate local solar time (LST)
export FINN_DATE_DEFINITION=UTC

# identifier of the af dataset
tag=modvrs_nrt_${yj}

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


# grab daily fire (two days)
token=INSERT_YOUR_TOKEN_HERE_FOR_FIRMS_NRT_DATA
# grab AF data
wget -e robots=off -m -np -R .html,.tmp -nH --cut-dirs=4 "https://nrt3.modaps.eosdis.nasa.gov/api/v2/content/archives/FIRMS/modis-c6.1/Global/MODIS_C6_1_Global_MCD14DL_NRT_${yjm1}.txt" --header "Authorization: Bearer ${token}" -P $data_dir
wget -e robots=off -m -np -R .html,.tmp -nH --cut-dirs=4 "https://nrt3.modaps.eosdis.nasa.gov/api/v2/content/archives/FIRMS/modis-c6.1/Global/MODIS_C6_1_Global_MCD14DL_NRT_${yj}.txt" --header "Authorization: Bearer ${token}" -P $data_dir
wget -e robots=off -m -np -R .html,.tmp -nH --cut-dirs=4 "https://nrt3.modaps.eosdis.nasa.gov/api/v2/content/archives/FIRMS/suomi-npp-viirs-c2/Global/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_${yjm1}.txt" --header "Authorization: Bearer ${token}" -P $data_dir
wget -e robots=off -m -np -R .html,.tmp -nH --cut-dirs=4 "https://nrt3.modaps.eosdis.nasa.gov/api/v2/content/archives/FIRMS/suomi-npp-viirs-c2/Global/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_${yj}.txt" --header "Authorization: Bearer ${token}" -P $data_dir

# grab annual global raster (can be commented out if you know that it's already imported into the database)
python3 $exc_dir/work_raster.py -y ${yrm2}


if [ $? -ne 0 ]; then
	echo problem in work_raster.py
	exit 1
fi



# process af
python3 $exc_dir/work_nrt.py -t $tag -y $yrm2 \
	-o $out_dir \
       	-fd $yj -ld $yj \
        -s $summary_file \
	$data_dir/FIRMS/modis-c6.1/MODIS_C6_Global_MCD14DL_NRT_${yjm1}.txt \
	$data_dir/FIRMS/modis-c6.1/MODIS_C6_Global_MCD14DL_NRT_${yj}.txt \
	$data_dir/FIRMS/suomi-npp-viirs-c2/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_${yjm1}.txt \
	$data_dir/FIRMS/suomi-npp-viirs-c2/SUOMI_VIIRS_C2_Global_VNP14IMGTDL_NRT_${yj}.txt

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
