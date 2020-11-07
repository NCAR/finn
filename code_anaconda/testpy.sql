create extension if not exists plpython3u;

create or replace function python_ver()
returns text as
$$
    import sys
    s = str(sys.version).replace('\n', '')
    
    return(s)
$$ 
language plpython3u volatile;
select python_ver();

create or replace function python_path()
returns setof text as
$$
    import sys
    s = list(sys.path)
    
    return(s)
$$ 
language plpython3u volatile;
select python_path();

create or replace function python_pkgs()
returns setof text as
$$
    import numpy as np
    import scipy as sp
    import networkx as nx
    o = []
    o += [ 'numpy: ' + np.__version__ ]
    o = o + [ 'scipy: ' + sp.__version__ ] 
    o = o + [ 'networkx: ' + nx.__version__ ]
    
    return(o)
$$ 
language plpython3u volatile;

select python_pkgs()
