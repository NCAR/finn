# miscelaneous book keeping and diagnostic tasks
import os
import subprocess
import sys

def summarize_log(tag, out_file = None):

    if out_file is None:
        out_file = sys.stdout
    

    schema = 'af_%s' % tag
    cmd = ['psql', '-f', 
         os.path.join(os.path.dirname(__file__), 'summarize_log.sql'),
                '-v', ('tag=%s' % tag), ]
    print(cmd)
    p = subprocess.run(cmd, check=True, stdout=subprocess.PIPE)
    out_file.write(p.stdout.decode())


def pesistence_analysis(tag):
    pass
