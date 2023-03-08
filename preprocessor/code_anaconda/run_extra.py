# miscelaneous book keeping and diagnostic tasks
import os
import subprocess
import sys
import psycopg2

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

def db_use_af(tag_af, outfile = None):
    if outfile is None:
        outfile = sys.stdout
    qry_af = """SELECT table_schema || '.' || table_name AS table_full_name,
    pg_size_pretty(pg_total_relation_size('"' || table_schema || '"."' || table_name || '"')) AS size
    FROM information_schema.tables
    WHERE table_schema = '%(sch_af)s'   
    ORDER BY pg_total_relation_size('"' || table_schema || '"."' || table_name || '"') DESC;""" % dict( 
            sch_af=('af_%s' % tag_af),
            ) 
            
    qry_af_tot = """SELECT table_schema,
    pg_size_pretty(sum(pg_total_relation_size('"' || table_schema || '"."' || table_name || '"'))) AS size
    FROM information_schema.tables
    WHERE table_schema = '%(sch_af)s'   
    GROUP BY table_schema;""" % dict(
        sch_af=('af_%s' % tag_af),
        )


    outfile.write('Disk use by AF processing intermediate tables inside the database\n\n')
    p = subprocess.run(['psql', '-d', 'finn', '-c', qry_af], stdout=subprocess.PIPE, check=True)
    outfile.write(p.stdout.decode() + '\n')

    outfile.write('Total\n\n')
    p = subprocess.run(['psql', '-d', 'finn', '-c', qry_af_tot], stdout=subprocess.PIPE, check=True)
    outfile.write(p.stdout.decode() + '\n')

def clean_db_af(tag_af, rasters):
    # cleans intermediate vectors, but be a bit more selective, going after big ones only

    schema = f"af_{tag_af}"
    conn = psycopg2.connect(dbname=os.environ['PGDATABASE'])
    cur = conn.cursor()
            

    # go over af_in_X (assuming that shape file is there and canbe restored if it's needed)
    cur.execute(f'''select table_name from "{schema}".af_ins;''')
    cur2 = conn.cursor()
    for rec in cur:
        tblname = rec[0]
        cmd = f'''drop table "{schema}".{tblname};'''
        print(cmd)
        cur2.execute(cmd)
        conn.commit()

    # go out_XXX, drop them except the final one (definitely dont need the intermeds)
    tblname = f"out"
    for rstinfo in rasters[:-1]:
        rstname = rstinfo['tag']
        tblname += ('_' + rstname)
        cmd = f'''drop table "{schema}".{tblname};'''
        print(cmd)
        cur2.execute(cmd)
        conn.commit()

    for rstinfo in rasters:
        rstname = rstinfo['tag']
        tblname = 'tbl_' + rstname
        cmd = f'''drop table if exists "{schema}".{tblname};'''
        print(cmd)
        cur2.execute(cmd)
        conn.commit()

    # drop work_div and work_lrg as well?  work_div has equivalent output as out_XXX with extra columns.  work_lrg should be reproduced by aggregating divided polyton if needed
    for tblname in ('work_lrg', 'work_div'):
        cmd = f'''drop table "{schema}".{tblname};'''
        print(cmd)
        cur2.execute(cmd)
        conn.commit()


def purge_db_af(tag_af, outfile=None):
    if outfile is None: outfile = sys.stdout
    # cleans intermediate vector
    sch_af = 'af_%s' % tag_af
    qry = 'DROP SCHEMA "%s" CASCADE;' % sch_af
    cmd = ['psql',  '-d', os.environ["PGDATABASE"], '-c', qry]
    
    outfile.write(f'Purging database schema for AF processing in {sch_af}\n')
    p = subprocess.run(cmd, check=True, stdout=subprocess.PIPE)
    outfile.write(p.stdout.decode() + '\n')

def disk_use_raster(year_rst, ddir_lct, ddir_vcf, outfile=None):
    if outfile is None: outfile = sys.stdout

    outfile.write('Disk use by downloaded {year_rst} raster hdf files\n')
    cmd = ['du', '-csh', ddir_lct, ddir_vcf]
    p = subprocess.run(cmd, stdout=subprocess.PIPE)
    outfile.write(p.stdout.decode() + '\n')

    outfile.write('Disk use by intermediate {year_rst} raster processing files\n')
    cmd = ['du', '-csh', workdir_lct, workdir_vcf]
    p = subprocess.run(cmd, stdout=subprocess.PIPE)
    outfile.write(p.stdout.decode() + '\n')

def db_use_raster(year_rst, tag_lct, tag_vcf, outfile=None):
    if outfile is None: outfile = sys.stdout

    qry_rst = """SELECT table_schema || '.' || table_name AS table_full_name,
    pg_size_pretty(pg_total_relation_size('"' || table_schema || '"."' || table_name || '"')) AS size
    FROM information_schema.tables
    WHERE table_name ~ '^.*(%(tbl_lct)s|%(tbl_vcf)s)'   
    ORDER BY pg_total_relation_size('"' || table_schema || '"."' || table_name || '"') DESC;""" % dict(
                tbl_lct=('rst_%s' % tag_lct),
                    tbl_vcf=('rst_%s' % tag_vcf),
                    )
    qry_rst_tot = """SELECT table_schema,
    pg_size_pretty(sum(pg_total_relation_size('"' || table_schema || '"."' || table_name || '"'))) AS size
    FROM information_schema.tables
    WHERE table_name ~ '^.*(%(tbl_lct)s|%(tbl_vcf)s)'   
    GROUP BY table_schema;""" % dict(
                    tbl_lct=('rst_%s' % tag_lct),
                        tbl_vcf=('rst_%s' % tag_vcf),
                        )
    outfile.write(f'Disk use by {year_rst} raster dataset in the database\n\n')
    p = subprocess.run(['psql', '-d', 'finn', '-c', qry_rst], stdout=subprocess.PIPE, check=True)
    outfile.write(p.stdout.decode() + '\n')
    outfile.write('Total for %(tag_lct)s and %(tag_vcf)s\n\n' % dict(tag_lct=tag_lct, tag_vcf=tag_vcf))
    p = subprocess.run(['psql', '-d', 'finn', '-c', qry_rst_tot], stdout=subprocess.PIPE, check=True)
    outfile.write(p.stdout.decode() + '\n')

def purge_hdf_raster(year_rst, ddir_lct, ddir_vcf, outfile=None):
    if outfile is None: outfile = sys.stdout

    # ditch entire download directory for the year
    tgts = [ddir_lct, ddir_vcf]
    cmd = ['rm', '-fr', ] + tgts
    outfile.write(f'Deleting downloaded *.hdf raster files for {year_rst} in\n\t{ddir_lct}\n\t{ddir_vcf}\n\n')
    p = subprocess.run(cmd, check=True)
                            

def purge_tif_raster(year_rst, workdir_lct, workdir_vcf):
    if outfile is None: outfile = sys.stdout

    # ditch entire processing directory 
    tgts = [workdir_lct, workdir_vcf]
    cmd = ['rm', '-fr', ] + tgts
    outfile.write(f'Deleting intermediate *.tif raster files for {year_rst} in\n\t{workdir_lct}\n\t{workdir_vcf}\n\n')
    subprocess.run(cmd, check=True)
def purge_db_reaster(year_rst):
    if outfile is None: outfile = sys.stdout

    outfile.write(f'Purging database tables for {year_rst}\n')
    rst_import.drop_tables(tag_lct)
    rst_import.drop_tables(tag_vcf)

                                                                    

