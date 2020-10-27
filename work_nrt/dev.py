import subprocess
import os
import sys
import psycopg2

def for_pycharm():
    os.environ['PGDATABASE'] = 'finn'
    os.environ['PGPASSWORD'] = 'finn'
    os.environ['PGUSER'] = 'finn'



def main(out=None):
    for_pycharm()
    if out is None:
        out = sys.stdout

    out.write('system environment inside docker container, for debugging purpose\n\n')
    out.write('\n'.join([k + '=' + os.environ[k] for  k in sorted(os.environ)]) + '\n\n')

    conn = psycopg2.connect(dbname = os.environ['PGDATABASE'])
    cur = conn.cursor()
    cur.execute('select version();')
    o = cur.fetchall()
    out.write('PostgreSQL version : ' + o[0][0] + '\n')

    cur.execute('select postgis_full_version();')
    o = cur.fetchall()
    out.write('PostGIS version : ' + o[0][0] + '\n')
    #print(o)

    with open('../code_anaconda/testpy.sql') as f:
        sql = f.read()
        try:
            o = cur.execute(sql)
        except psycopg2.errors.DuplicateObject:
            pass
    print(o)



main()

