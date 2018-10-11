Wed Sep 26 12:44:15 MDT 2018

this is how i would run on modeling1 at acom.ucar.
original instruction was for wranger at tacc.utexas.

	Tue Apr  4 09:22:35 CDT 2017

big change on how to run the sql code (parts 3-5, 3-6), as i was using "launcher"
(https://www.tacc.utexas.edu/research-development/tacc-software/the-launcher)
overthere.  I am rewriting that part into some kind of script.

1. raster:
1-1. download lct/vcf with wget, to $DATA/download/e4ftl01.cr.usgs.gov/

1-2. "$DATA/raster_try6_6sec_importfirst" has script to preprocess/import raster
into postgis.  in "lct" and "vcf" subdir, there are "rst_import5_???.py" .  run it
with year as arguments, eg

python rst_import5_lct.py 2013

this should create subdir "global_2013", do some processing there includeing
resampling.  "proc_????/rsp" dir (???? is year) has ready-to-import raster, in
WGS84 projection, tiled to 10x10 degree.  script import those into schema
"raster_6sec" as table "lct_global_2013".

The python script has main() function near end, and it has a few if-then
block, which is swith for working on each subpocessing steps.  the last block
is for imporing, the remaining erarlier blocks are preparing data.  So for
some reason you have to run part of this stream, eg.  only import failed, then
change other steps to False to skip them, and just run import.

This import takes fairly long time, didnt measure but i feel like an hour or
more for one year of vcf (lct is faster)

2. fire point:

2-1. download v6 modis detections from firms web interface, save it into :
"$DATA/firms.modaps.eosdis.nasa.gov/????", ???? being year.  expand zip in the
directory.    (used in step 3-2 below)

3. main processing

Done in directories $WORK/finn_code/run_201703_revisit_step1/global_????, ????
being year. 

3-1.
(have scripts) got template set of files.  I recommend copying from
global_2016.  files to copy are:

mklst_step1.py
mklst_step2.py
import_af.sh
run.step1.sh
run.step2.sh
export_shp.sh
step1_prep_v5f.sql
step1_work_v5f.sql
step2_prep_v3h.sql
step2_work_v3h.sql

or basically "cp *.py *.sh *.sql

3-2. 

(import fire) edit "import_af.sh" to have year to be the year of processing,
and change "archname" to the download id for particular dataset.  For example,
i got DL_FIRE_M6_9252.zip for global 2013 fire, expanded files includes
fire_archive_M6_9252.shp.  In this chhase archname is set to "M6_9252"

[!!BE EXTREMELY CARFUL!!] that this script is going to ditch the schema first.
So if, for example,  you process one year, and then move to next year, but
forgetting to update this script's year would erase what you did for the other
year!!

run the script, which s probably 10 to 15 min.

3-3.

(make command line list)  edit "mklst_step?.py".  this script is going to
create psql command which tells to process one day of a year.  I use TACC's
launcher tool to process day by day.  anyways, what you need to edit is "yr"
to be year of processing.  once done, run it e.g.

python mklst_step1.py

this should create "commandlines.step?".

3-4.
(edit sql files) 

There are 4 sql scripts, 

step1_prep_v5f.sql
step1_work_v5f.sql
step2_prep_v3h.sql
step2_work_v3h.sql

each file has near the top a command like below.

SET search_path TO global_2016,public;

change "global_2016" part to match the year of processing.  do the same for
each four.

Then for the last one step2_work_v3h.sql, there are two more lines to edit,
which specify the raster year to be used for each of lct and vcf.  edit them
to match the year of raster to use (e.g, 2012 for 2012 processing)

\set vcf_yr 2015
\set lct_yr 2013

3-5.
(edit run.step?.sh files)

run.step?.sh doesnt need editing, actually, except the case where you want to
udpate the version of script (i used v5f for first step, v3h for second step)

3-6.
(run)

finally ready to run.  On wrangler, you either

option 1) from login node,
sbatch run.step1.sh

option 2) from reserved compute node
sh run.step1.sh

I recommend second method in production runs.  First method is going to get
compute node assigned, and i fire up data base on the node (that mean i have
to shut down it if it is used in other places), do the processing and then
finish. It works, but if you have many tasks to acoomplish, it's not that
convenient

Second method, you have to get a node first, either reserve node from XCEDE (i
never done that) or "idev -t 48:00:00" to grab a node for two days, for
example.  Once i got a node, i login to the node (e.g. c from the "login" node
(e.g c251-103, idev tells you which node you got).  Then from there you run
the script "sh run.step1.sh" for example.

you have to run step1, then step2, obviously.  

each creates a bunch of log file out.step1.o0, out.step1.o1, ....   *.o0 is
log from prep script.  o1 to o366 is log from each.  i usually save them into
subdirectory logs.step1 and logs.step2

again, i haven't measured, but i feel like step1 takes 15 min or so, step2
takes longer but i think it runs in like 40 min.

3-7.
(review logs)
i'd open a few of them see they just logs calculation sub-steps without
obvious problem.

I also 
grep ERROR out.step1.o*

this shouldn't turn back anything.  if it does, open the file with problem,
and see what's going on, resolve, rerun.

In addition to checking error For step2, i run

grep WARN out.step2.o*

this will return some error from "st_clip_fuzzy()" runction i wrote.  it is
supposed to go around the issue where polygon barely intersects with tiled
raster.  each problem returns four line like below:

out.step2.o5:psql:step2_work_v3h.sql:113: WARNING:  st_clip_fuzzy: intersection POLYGON((20.4 9.27799999986263,20.4 9.27799999866151,20.3999999998828 9.27799999971615,20.4 9.27799999986263))
out.step2.o5:psql:step2_work_v3h.sql:113: WARNING:  st_clip_fuzzy: area intersection 7.03754086306891e-20
out.step2.o5:psql:step2_work_v3h.sql:113: WARNING:  st_clip_fuzzy: area pixel 2.77777777777777e-06
out.step2.o5:psql:step2_work_v3h.sql:113: WARNING:  st_clip_fuzzy: area ratio 2.53351471070482e-14

first line tells the problematic tiny intersection, second line its area
(square of degrees), 3rd line size of pixel (always 6sec by 6sec), forth line
is area of intersection per pixel.  this value is supposed to be real tiny,
and my action is pretend that it never intesected.  if this intersection was
quite large, e.g. larger than a pixel, then my assumption is wrong and
ignoreing this intersection has consequence.  So that should be ERROR, not
warning and i should fix the problem.  But ia m running out of time and i dont
know what to do for those case at this time anyway.  So i just let it go, that
particula fire have erratic value, but it's rare anyway.

3-8.

(export)
edit export_shp.sh for yr=xxxx .  this will create shp file of the subdivided
polygons with land cover identified

this takes 10 min or so, i think, maybe longer.


