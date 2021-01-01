import pandas as pd
import numpy as np

def prep(fname):
    df = pd.read_csv(fname)
    df['cen_lon'] = df['cen_lon'].apply(lambda x:format(x, '.5f'))
    df['cen_lat'] = df['cen_lat'].apply(lambda x:format(x, '.5f'))
    df['area_sqkm'] = df['area_sqkm'].apply(lambda x:format(x, '.5f'))
    df['f_lct'] = df['f_lct'].apply(lambda x:format(x, '.3f'))
    df['v_tree'] = df['v_tree'].apply(lambda x:format(x, '.3f'))
    df['v_herb'] = df['v_herb'].apply(lambda x:format(x, '.3f'))
    df['v_bare'] = df['v_bare'].apply(lambda x:format(x, '.3f'))
#    if 'v_frp' in df.columns:
#        df['v_frp'] = df['v_frp'].apply(lambda x:format(x, '.1f'))
    return df

def compare(fname0, fname1, difference_only=True):

    df0 = prep(fname0)
    df1 = prep(fname1)

    df0 = df0.set_index([_ for _ in df0.columns if _ not in ('fireid', 'polyid')])
    df1 = df1.set_index([_ for _ in df1.columns if _ not in ('fireid', 'polyid')])

    assert df0.index.is_unique
    assert df1.index.is_unique


#    if difference_only:
#        dfo = pd.concat( [ 
#            df0[df0.index.isin(set(df0.index).difference(df1.index))], 
#            df1[df1.index.isin(set(df1.index).difference(df0.index))], 
#            ])
#    else:
#        dfo = df0.join(df1, how='outer', lsuffix='_l', rsuffix='_r')

    dfo = df0.join(df1, how='outer', lsuffix='_l', rsuffix='_r')
    if difference_only:
        dfo = dfo.loc[dfo.fireid_l.isna() | dfo.fireid_r.isna() ]
    dfo = dfo.reset_index()
    print(dfo.columns[-4:])
    print(dfo.columns[:-4])
    print(list(dfo.columns[-4:]) + list(dfo.columns[:-4]))
    dfo = dfo.reindex(list(dfo.columns[-4:]) + list(dfo.columns[:-4]), axis=1)
    return dfo
    


if __name__ == '__main__':
    import sys

    fname0 = sys.argv[1]
    fname1 = sys.argv[2]


    df = compare(fname0, fname1, difference_only=True)
    if len(df.index) == 0:
        print('no difference')
    else:
        print('differs, see "diff.csv"')
        oname = 'diff.csv'
        df.to_csv(oname, index=False)
