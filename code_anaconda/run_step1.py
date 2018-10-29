# based on
# https://stackoverflow.com/questions/4992400/running-several-system-commands-in-parallel

from subprocess import Popen, PIPE
import datetime
import os

def main(tag, dt0, dt1, vorimp='scipy', gt=3, buf0=False, ver=None):

#    yr=2016

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


    #max_procs = 6 # ask Garth or somebody how many process would be approprite...
    max_procs = 2

    # run the prep script
    if True:


        print("starting prep: %s" % datetime.datetime.now())
        fo = open('out.step1.o0', 'w')
        p = Popen( 
            ['psql'] + 
            ['-f', ('step1_prep_%s.sql' % ver)] +
            ['-v', ("tag=%s" % tag)],
            stdout = fo)

        p.communicate()
        if p.returncode >0:
            print(p)
            print(dir(p))
            print(p.stderr)
            raise RuntimeError()

    if True:

        dates = [dt0 + datetime.timedelta(days=n) for n in
                range((dt1-dt0).days)]

        procs = set()
        for dt in dates:

            print("starting work %s: %s" % (dt.strftime('%Y-%m-%d'), datetime.datetime.now()))
            

#            procs.add(Popen(
#                ['psql',] +
#                ['-f', ('step1_work_%s.sql' % ver)] +
#                ['-v', ("tag=%s" % tag)] +
#                ['-v', ("oned='%s'" % dt.strftime('%Y-%m-%d'))],
#                    stdout = open('out.step1.o%s' % dt.strftime('%Y%m%d'),
#                        'w')
#                    )) 
#            if len(procs) > max_procs:
#                os.wait()
#                procs.difference_update(
#                        [p for p in procs if p.poll() is not None]
#                        )
#            for p in procs:
#                if p.poll() is None:
#                    p.wait()
#
            # alright, just one at a time...
            p = Popen(
                ['psql',] +
                ['-f', ('step1_work_%s.sql' % ver)] +
                ['-v', ("tag=%s" % tag)] +
                ['-v', ("oned='%s'" % dt.strftime('%Y-%m-%d'))],
                    stdout = open('out.step1.o%s' % dt.strftime('%Y%m%d'),
                        'w')
                    ) 
            p.communicate()
            if p.returncode >0:
                raise RuntimeError()




