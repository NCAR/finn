import os
import subprocess
import shlex

# destination in db
schema = 'raster'

def main(tag_tbl, shpname=None, tag_var=None):
    if shpname is None:
        shpname = 'all_countries/All_Countries.shp'
    
    # create schema if needed
    cmd = 'psql -c "CREATE SCHEMA IF NOT EXISTS %s;"' %  schema
    subprocess.run(shlex.split(cmd))

    dstname = schema + '.' + '_'.join(['rst', tag_tbl])

    # drop table if it already exists, warn???
    cmd = 'psql -c "DROP TABLE IF EXISTS %s;"' %  dstname
    subprocess.run(shlex.split(cmd))

    cmd = 'shp2pgsql -d -c -s 4326 -I'.split()
    cmd += [shpname]
    cmd += [dstname]
    print(cmd)
    fo = open('import_%s.log' % tag_tbl, 'w')
    p1 = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    p2 = subprocess.Popen(['psql', ], stdin=p1.stdout, stdout=fo)
    p2.communicate()
