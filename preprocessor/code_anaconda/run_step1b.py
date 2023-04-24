# based on
# https://stackoverflow.com/questions/4992400/running-several-system-commands-in-parallel
import subprocess
from subprocess import Popen, PIPE, DEVNULL, STDOUT
import datetime
import os
import shlex
import psycopg2
import time

# somehow, Mac version of docker appeared to be confuesed in encoding
# i tell explicitly here that it is utf-8
# right now (2019-09-20), step1 are the only part where i use "psql -f"
# so setting it here would make sense, unless there is something more global
os.environ['PGCLIENTENCODING']='utf-8'

def get_first_last_day(tag):
    """Returns first and last day from active fire table"""

    schema = 'af_%s' % tag

    oned = datetime.timedelta(days=1)

    # get connection
    conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])
    cur = conn.cursor()

    # make sure that work_pnt exists.
    cur.execute('select exists(select * from information_schema.tables where table_schema = \'%s\' and table_name=\'work_pnt\')' % schema)
    has_work_pnt = cur.fetchall()[0]
    if not has_work_pnt:
        raise RuntimeError("cannot find work_pnt.  run step1_prep first.")

    # get first/last day from the data
    cur.execute('select min(acq_date_lst), max(acq_date_lst) from "%s".work_pnt' % (schema))
    dt01 = cur.fetchall()[0]
    print(dt01)

    # see if dup. toropics was done for modis
    cur.execute('select count(*) from "%s".work_pnt where instrument = \'MODIS\' and abs(lat) <= 30' % (schema))
    cnt_tropdup = cur.fetchall()[0][0]
    print(cnt_tropdup)
    if cnt_tropdup > 0:
        # trop fire should have been duplicated to carry over to next day
        # that means first day of the dataset is incomplete (missing carry over from the previous day)
        first_day = dt01[0] + oned
    else:
        # can start using the first day's data
        first_day = dt01[0]
    last_day = dt01[1]
    
    return (first_day, last_day)

# TODO make dt0 and dt1 to be first_day/last_day, and dont use python's indexing, make it more transparent.  do adjustment in run_step?.py files
def main(tag, first_day=None, last_day=None, vorimp='scipy', gt=3, buf0=False, ver='v7m', run_prep=True, run_work=True,
        filter_persistent_sources = False,
        date_definition = 'LST'
        ):
   

    if date_definition not in ('LST', 'UTC'):
        raise ValueError(f"date_definition has to be 'LST' or 'UTC': '{date_definition}'")

    schema = 'af_%s' % tag

    if ver is None:
        
        if vorimp == 'scipy':
            # scipy implementation for vor
            if gt == 3:
                ver='v5f'
            elif gt == 2:
                ver='v7f'

        elif vorimp == 'scipy_fixcutter':
            if gt == 3:
                ver='v7g' # original version
        elif vorimp == 'scipy_fixcutter_v7h':
                # trying to cleaning up...,  i intended to drop thin ones, but that doesnt seem to be big problem with this scipy/qgis version
                ver='v7h'  
        elif vorimp == 'scipy_fixcutter_v7i':
                # i am not ready to move thing into geography, too much to worry about.  
                # stick with geometry and st_area(geom, true)
                ver='v7i'
        elif vorimp in ('scipy_fixcutter_v7j',
                'scipy_fixcutter_fixextent'):
                ver='v7j'

        elif vorimp == 'postgis':
            # postgis implementation for vor
            if gt == 3:
                # vornoi approach for npnt > 3
                ver='v7b'
            elif gt == 2:
                # vornoi approach for npnt > 2
                if not buf0:
                    ver='v7c'

                else:
                    ver='v7d'
            elif gt == 1:
                if not buf0:
                    raise RuntimeError()
                else:
                    ver='v7e'
        else:
            raise RuntimeError('Unknown vorimp: %s' % vorimp)

    max_procs = 2

    # run the prep script
    if run_prep:
        print("starting prep: %s" % datetime.datetime.now())

        def to_date(x):
            if x is None:
                o = ''
            else:
                # datetime
                o = x.strftime('%Y-%m-%d')
            return o
            
        with open('out.step1b.prep', 'w') as ofile:

            cmd = ['psql','-f',  os.path.join(os.path.dirname(__file__), ('step1b_prep_%s.sql' % ver)), 
                    '-v', ('tag=%s' % tag), 
                    '-v', ('filter_persistent_sources=%s' %  filter_persistent_sources),
                    '-v', ('date_range=%s' %  f"[{to_date(first_day)},{to_date(last_day)}]"),
                    '-v', ('date_definition=%s' %  date_definition), 
                    ]
            print(cmd)
            maxtry = 3
            for itry in range(maxtry):
                try:
                    subprocess.run(cmd, check=True, stderr=STDOUT, stdout=ofile)
                except subprocess.CalledProcessError as err: 
                    if itry +1 >= maxtry:
                        raise
                    print(f"\ngot this ERROR from 'step1_prep': \n\n", err.stderr.decode(),)
                    print(f"retry in {30*itry} sec")
                    time.sleep(30*itry)
                    continue
                break


    else:
        pass


    if run_work:
        if first_day is None or last_day is None:
            first_day, last_day = get_first_last_day(tag)

        dt0 = first_day
        dt1 = last_day + datetime.timedelta(days=1)

        dates = [dt0 + datetime.timedelta(days=n) for n in
                range((dt1-dt0).days)]

        procs = set()
        for dt in dates:
            print("starting work %s: %s" % (dt.strftime('%Y-%m-%d'), datetime.datetime.now()))
            cmd = ['psql',] + ['-f', (os.path.join(os.path.dirname(__file__), ('step1b_work_%s.sql' % ver)))]
            cmd += ['-v', ("tag=%s" % tag)] + ['-v', ("oned='%s'" % dt.strftime('%Y-%m-%d'))]
            ofile = open('out.step1b.o{0}'.format( dt.strftime('%Y%m%d')), 'w')
            #print(cmd)
            #subprocess.run(shlex.split(cmd), check=True)
            try:
                subprocess.run(cmd, check=True, stderr=STDOUT, stdout=ofile)
            except subprocess.CalledProcessError as err: 
                print(f"\nERROR from 'step1b_work': \n\n", err.stderr.decode(),)
                raise
#        print("starting post %s: %s" % (dt.strftime('%Y-%m-%d'), datetime.datetime.now()))
#        cmd = ['psql',] + ['-f', (os.path.join(os.path.dirname(__file__), ('step1_post.sql' )))]
#        cmd += ['-v', ("tag=%s" % tag)] 
#        print(cmd)
#        try:
#            subprocess.run(cmd, check=True, stderr=PIPE)
#        except subprocess.CalledProcessError as err: 
#            print(f"\nERROR from 'step1_post': \n\n", err.stderr.decode(),)
#            raise
