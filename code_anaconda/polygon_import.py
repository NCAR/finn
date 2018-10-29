import os
from subprocess import Popen, PIPE
# -----------------
#   destination db
# -----------------
# destination in db
schema = 'raster'

def main(shpname, tag_tbl, tag_var=None):
    # create schema if needed
    cmd = 'psql -c "CREATE SCHEMA IF NOT EXISTS %s;"' %  schema
    os.system(cmd)

    dstname = schema + '.' + '_'.join(['rst', tag_tbl])

    # drop table if it already exists, warn???
    cmd = 'psql -c "DROP TABLE IF EXISTS %s;"' %  dstname
    os.system(cmd)

    cmd = 'shp2pgsql -d -c -s 4326 -I'.split()
    cmd += [shpname]
    cmd += [dstname]
#    cmd += tifnames
    print(cmd)
    fo = open('import_%s.log' % tag_tbl, 'w')
    p1 = Popen(cmd, stdout=PIPE)
    p2 = Popen(['psql', ], stdin=p1.stdout, stdout=fo)
    print( p2.communicate())
            

