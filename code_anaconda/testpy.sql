create or replace function testpy()
returns text as
$$
    import sys
    s = str(sys.version)
    import numpy as np
    import networkx as nx
    s = s + ' | numpy: ' + np.__version__
    s = s + ' | networkx: ' + nx.__version__
    
    #plpy.notice(s)
    s2 = str(sys.path)
    #plpy.notice(2)
    return(s)
$$ 
language plpython3u volatile;

select testpy()
