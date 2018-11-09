# FINN Preprocessor

PostGIS based preprorcessor.  Given point feature of active fire detections, this code estimates burned region, and then determine land cover on the burned area.

## Instructions

### Download MODIS land cover and vegetation data

```
bash download-land-cover.sh
bash download-vcf.sh
```

```
docker run -v $(pwd):/home/finn --name 'finn' -p 5432:5432 -p 8888:8888 -d finn
docker exec -it finn jupyter notebook --ip=0.0.0.0 --port=8888 --allow-root
```
