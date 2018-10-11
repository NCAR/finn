# based on
# https://stackoverflow.com/questions/4992400/running-several-system-commands-in-parallel

from subprocess import Popen, PIPE
import datetime
import os

yr=2016
ver='v5f'

max_procs = 6 # ask Garth or somebody how many process would be approprite...
#max_procs = 2

# run the prep script
if True:
    print "starting prep: %s" % datetime.datetime.now()
    fo = open('out.step1.o0', 'w')
    p = Popen( ("psql -d finn -f step1_prep_%s.sql" % ver).split(), stdout=fo )
    p.communicate()

if True:

    dt0 = datetime.date(yr,1,1)
    dt1 = datetime.date(yr+1,1,1)
    dates = [dt0 + datetime.timedelta(days=n) for n in
            range((dt1-dt0).days)]
    #print dates
    #dates = dates[:4]

    procs = set()
    for dt in dates:

        print "starting work %s: %s" % (dt.strftime('%Y-%m-%d'), datetime.datetime.now())
        

        procs.add(Popen(
            'psql -d finn'.split() +
            ['-f', ('step1_work_%s.sql' % ver)] +
            ['-v', ("oned='%s'" % dt.strftime('%Y-%m-%d'))],
                stdout = open('out.step1.o%s' % dt.strftime('%Y%m%d'),
                    'w')
                )) 
        if len(procs) > max_procs:
            os.wait()
            procs.difference_update(
                    [p for p in procs if p.poll() is not None]
                    )
        for p in procs:
            if p.poll() is None:
                p.wait()





