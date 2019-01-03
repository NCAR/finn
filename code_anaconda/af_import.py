import os
import subprocess
from subprocess import Popen, PIPE
import shlex

def main(tag, fnames):
    if isinstance(fnames, str):
        fnames = [fnames]
    schema = 'af_' + tag
    dstname = schema + '.' + 'af_in'
    cmd = 'psql -c "DROP SCHEMA IF EXISTS %s CASCADE;"' %  schema
    os.system(cmd)
    cmd = 'psql -c "CREATE SCHEMA %s;"' % schema
    print(cmd)
    os.system(cmd)

    for i,fname in enumerate(fnames):
        if len(fnames) == 1:
            tblname = 'af_in'
        else:
            tblname = 'af_in_%d' % (i+1)

        if False:
            # ogr2ogr is better because this reads non-standard, larger dbf file.
            # but i screwed up my anaconda and ogr2ogr does not load properly now
            # so the shp2pgsql method is what i am using
            cmd = 'shp2pgsql -d -c -s 4326 -I'.split()
            cmd += [fname]
            cmd += [dstname]
            fo = open('import_%s.log' % tag, 'w')
            p1 = Popen(cmd, stdout=PIPE)
            p2 = Popen(['psql',], stdin=p1.stdout, stdout = fo)
            p2.communicate()
        else:
            dbname = os.environ.get('PGDATABASE', 'finn')
            #print(os.environ)
            cmd = 'ogr2ogr -progress -f PostgreSQL -overwrite'.split()
        #    if 'PGUSER' in os.environ: conn['user'] = os.environ['PGUSER']
            #cmd += [ "PG:dbname='finn' user='postgres' password='finn'" ]
            cmd += [ "PG:dbname='%s'" % dbname]
            cmd += '-lco SPATIAL_INDEX=GIST'.split()
            #cmd += '-lco SPATIAL_INDEX=YES'.split()
            cmd += ('-lco SCHEMA='+schema).split()
            cmd += ('-lco GEOMETRY_NAME=geom').split()  # match with what shp2pgsql was doing
            cmd += ('-lco FID=gid').split()  # match with what shp2pgsql was doing
            cmd += ['-nln', tblname]
            cmd += [fname]
            print('\ncmd:\n%s\n' % ' '.join(cmd))
            print(cmd)
            subprocess.run(cmd)
#            p1 = Popen(cmd)#, stdout=PIPE)
        #    p2 = Popen(['psql',], stdin=p1.stdout, stdout = fo)
        #    print( p2.communicate())
#            p1.communicate()

if __name__ == '__main__':
    import sys
    tag = sys.argv[1]
    fnames = [sys.argv[2]]
    fnames += sys.argv[3:]

    main(tag, fnames)


