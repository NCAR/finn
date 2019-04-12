# miscelaneous book keeping and diagnostic tasks
import os
import subprocess

def summarize_log(tag):

    schema = 'af_%s' % tag
    cmd = ['psql', '-f', 
         os.path.join(os.path.dirname(__file__), 'summarize_log.sql'),
                '-v', ('tag=%s' % tag), ]
    print(cmd)
    p = subprocess.run(cmd, check=True, stdout=subprocess.PIPE)
    print(p.stdout.decode())


def pesistence_analysis(tag):
    pass
