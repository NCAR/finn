# based on
# https://stackoverflow.com/questions/4992400/running-several-system-commands-in-parallel
import subprocess
from subprocess import Popen, PIPE
import datetime
import os
import shlex

def main(tag, dt0, dt1, vorimp='scipy', gt=3, buf0=False, ver=None, run_prep=True, run_work=True):
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
        cmd = " ".join(['psql'] + ['-f', ('step1_prep_%s.sql' % ver)] + ['-v', ("tag=%s" % tag)])
        subprocess.run(shlex.split(cmd), check=True)
    else:
        pass


    if run_work:
        dates = [dt0 + datetime.timedelta(days=n) for n in
                range((dt1-dt0).days)]

        procs = set()
        for dt in dates:
            print("starting work %s: %s" % (dt.strftime('%Y-%m-%d'), datetime.datetime.now()))
            cmd = ['psql',] + ['-f', ('step1_work_%s.sql' % ver)] + \
                           ['-v', ("tag=%s" % tag)] + ['-v', ("oned='%s'" % dt.strftime('%Y-%m-%d'))]
            #print(cmd)
            #subprocess.run(shlex.split(cmd), check=True)
            subprocess.run(cmd, check=True)
