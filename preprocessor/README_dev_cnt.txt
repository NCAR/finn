approach:

1. start with pnt feature set

2. rasterize above, using reolution of the piece of raster in raster dataset
   i have been using raster resolution of 6seconds (~180m), and 240x240 pixel for each
row of raster dataset.  So each raster data is 240x6=1440 sec = 0.4 degree

3. now i sould have 0.4x0.4 deg raster which is 0/1.  Based on this raster,
create raster dataset of 0s.  

postgis raster has largest unisgined integer of 32bit
or, may have 1bit raster.   Maybe have multip band raster of 1bit each...?

pixel size, 6 sec maybe too large?  lets go 1sec? (~30m)

4. now process each day.  get polygon.  rasterize to match the above
raster dataset, and mark the bit for the day


