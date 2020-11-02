-- schema name tag, prepended by af_
\set myschema af_:tag
-- to use in identifier in query.  without double quote it is converted to lower case
\set ident_myschema '\"' :myschema '\"'
-- to use as literal string
\set quote_myschema '\'' :myschema '\''

SET search_path TO :ident_myschema , public;
SHOW search_path;

-- filter persistanct source or not
\set my_filter_persistent_sources :filter_persistent_sources
\set

-- first/last date (in local time) to retain.  pass string of YYYY-MM-DD, or N
\set my_date_range '\'':date_range'\''
\set

\set ON_ERROR_STOP on

DO language plpgsql $$ begin
	RAISE NOTICE 'tool: start, %', clock_timestamp();
END $$;

DO language plpgsql $$ begin
	RAISE NOTICE 'tool: here, %', clock_timestamp();
END $$;
-------------------------------
-- Part 1: Setting up tables --
-------------------------------

-- make working table
DROP TABLE IF EXISTS work_pnt;
CREATE TABLE work_pnt (
	rawid integer,
	fireid integer,
	ndetect integer,
	geom_pnt geometry,
	lon double precision,
	lat double precision,
	scan double precision,
	track double precision,
	acq_date_utc date,
	acq_time_utc character(4),
	acq_date_lst date,
	acq_datetime_lst timestamp without time zone,
	instrument character(5),
	confident boolean,
	anomtype integer, -- "Type" field of AF product, 0-3
	geom_sml geometry
	);

DO language plpgsql $$ begin
	RAISE NOTICE 'tool: here, %', clock_timestamp();
END $$;

-- group pixels, and lone detections in one table of fire polygons
drop table if exists work_lrg;
create table work_lrg (
	fireid integer primary key not null,
	geom_lrg geometry,
	acq_date_lst date,
	ndetect integer,
	area_sqkm double precision
	);



drop table if exists work_div;
create table work_div (
	polyid serial primary key ,
	fireid integer,
	geom geometry,
	acq_date_lst date,
	area_sqkm double precision
	);

drop table if exists tbl_flddefs;
create table tbl_flddefs (
	instrument character(50),
	colname character(50),
	expression character(50)
);
insert into tbl_flddefs ( instrument, colname, expression)
values
('MODIS', 'confident', 'confidence > 20'),
('VIIRS', 'confident', 'confidence != ''l''')
;

DROP TABLE IF EXISTS tbl_options;
CREATE table tbl_options(
  opt_name varchar,
  opt_value varchar
);
INSERT INTO tbl_options (opt_name, opt_value)
VALUES
('filter_persistent_sources', :my_filter_persistent_sources ),
('date_range', :my_date_range )
;

DROP TABLE IF EXISTS tbl_log;
CREATE table tbl_log(
  log_id bigserial,
  log_event varchar,
  log_table varchar,
  log_nrec_change bigint,
  log_nrec_before bigint,
  log_nrec_after bigint,
  log_time_start timestamp,
  log_time_finish timestamp,
  log_time_elapsed interval
);


-------------------------------------------
-- Part 2: Function and Type definitions --
-------------------------------------------

CREATE OR REPLACE FUNCTION log_checkin(log_event varchar, log_table varchar, nrec bigint)
RETURNS bigint AS
$$
  INSERT INTO tbl_log (log_event, log_table, log_nrec_before, log_time_start)
  VALUES (log_event, log_table, nrec, clock_timestamp())
  RETURNING log_id;
$$
LANGUAGE sql;

CREATE OR REPLACE FUNCTION log_checkout(log_id_target bigint, nrec bigint)
RETURNS bigint AS
$$
  WITH foo AS (
    SELECT clock_timestamp() tnow
  )
  UPDATE tbl_log t SET 
  log_nrec_after = nrec,
  log_nrec_change = nrec - t.log_nrec_before, 
  log_time_finish = foo.tnow,
  log_time_elapsed = foo.tnow - t.log_time_start
  FROM foo
  WHERE t.log_id = log_id_target
  RETURNING log_nrec_change;
  ;
$$
LANGUAGE sql;

CREATE OR REPLACE FUNCTION log_purge(_log_event varchar)
RETURNS bigint AS
$$
  declare n bigint;
  begin
n := (select count(*) from tbl_log t where t.log_event = _log_event);

  DELETE FROM tbl_log t
  WHERE t.log_event = _log_event;


return n;
end;

$$
LANGUAGE plpgsql volatile;

----------------------------------------
-- Part 2.0: testpy (info for python) --
----------------------------------------
create or replace function testpy()
returns text as
$$
    import sys
    s = str(sys.version)
    import numpy as np
    import networkx as nx
    s = s + ' | numpy: ' + np.__version__
    s = s + ' | networkx: ' + nx.__version__
    
    plpy.notice(s)
    s2 = str(sys.path)
    plpy.notice(2)
    return(s)
$$ 
language plpython3u stable;

select testpy();

/* NOTE for plpython */
/* 

- i am not sure if i can pass a bunch of records to plpython.  only way i figure out is to let plpython to query and make data to work with on its own.
- i am not sure i can insert geometry from plpython.  geomoetry operations may needed be done by query
- so my plan now is to
    * get edges, and also have pair polygon for each
    * use networkx to identify connected components
    * for each edge in component, tag the edge table with smallest cleanid within the connected components (call this fielad as cleanid0)
    * use query to aggrgate the edge tables by cleanid0, geometries got st_union()
    * union of this aggregated edge table plus the orphant detection 
*/
-----------------------------------------
-- Part 2.1: pnt2grp (points to group) --
-----------------------------------------

drop type if exists p2grp cascade;
create type p2grp as (
	fireid integer,
	lhs integer,
	rhs integer,
	ndetect integer
);


-- given edges, return id of connected components to which it belongs to
-- edges are defined as two integer vectors lhs (verctor of id of start points) and rhs (end points)
-- return value is setof p2grp, which has 
--   fireid (lowest id within the component, which can be think of as id of connected component)
--   lhs (input)
--   rhs (input)
--   ndetect (count of nodes within components
create or replace function pnt2grp(lhs integer[], rhs integer[])
returns setof p2grp as
$$
    """given edges, return connected components"""
    import time, datetime
    #t0 = time.time()
    import networkx as nx
    g = nx.Graph()
    g.add_edges_from((l,r) for (l,r) in zip(lhs,rhs))
    plpy.notice("g.size(): %d, %s" % (g.size(), datetime.datetime.now()))
    #plpy.notice("g.order(): %d" % g.order())
    
    results = []
    #ccs = nx.connected_component_subgraphs(g)
    ccs = [g.subgraph(_).copy() for _ in nx.connected_components(g)]

    for sg in ccs:
        clean0 = min(sg.nodes())
        n = sg.order()
        for e in sg.edges():
            e = e if e[0] < e[1] else (e[1],e[0])
            results.append([clean0, e[0], e[1], n])
    #plpy.notice("elapsed: %d", (time.time() - t0)) 
    return results
    
$$ 
language plpython3u immutable;
-- language plpythonu volatile;

-----------------------------------------
-- Part 2.2: pnt2drop (points to drop) --
-----------------------------------------

-- info on points to drop
drop type if exists p2drp cascade;
create type p2drp as (
	id int,		-- pnt (cleanid) to be dropped
	others int[]	-- other members of pnts grouped together to be replaced by one pnt.  midpoint are to be filled in
);


-- given group of edges joining ponts that are close to each other,
-- identify which point to be skimmed so that remaining points are not connected each other
--
-- the function first identify conncted components, which represents group of points that are
-- close to each other, defined by the calling routine.
--
-- for each of connected components, points that has the highest score got eliminated
-- (score is determined for each pair by calling routine this by sum( 1 / distance_to_neigbor ))  
-- elimination is repeated unitl the group is not connected any more.
-- 
-- the algorism also specifies group of points which is to be replaced by centroid, not just dropped.
-- 

create or replace function pnt2drop(lhs integer[], rhs integer[], invdist double precision[])
returns setof p2drp as $$

    import networkx as nx
    # load all points into a graph
    g = nx.Graph()
    for (l,r,i) in zip(lhs,rhs,invdist):
        g.add_edge(l, r, invdist=i)

    # find nodes to drop

    todrop = []
    torepl = []
    added = {} # map from added node to dropped nodes
    iadd = 0 # id of filling (added) node

    # cc is a group of points (connected components) 
    # that is close to each other
    #for icc,cc in enumerate(nx.connected_component_subgraphs(g)):
    for icc,cc in enumerate(nx.connected_components(g)):
        cc = g.subgraph(cc).copy()

#        plpy.notice(icc, cc.size())
        ccs = cc.size() + 1

        # eliminate points until the subgraph nolonger is a graph
#        while cc.size() > 0:
        # ccs is points within connnected component, and double that number should be
        # far more than enough iteration, unless there is some unforeseen problem in algorithm
        for xx in range(ccs*2):
#            plpy.notice('here0')
            if xx == ccs*2: plpy.error(xx)
            if cc.size() == 0: break

            assert ccs > cc.size()
#            plpy.notice('here1')

            # for each node,  calculate sum of invdist
            # and determine node(s) which has maximum value
            m = 0
            mydrop = []
            for n, nbr in cc.adjacency():
                s = sum(_['invdist'] for _ in nbr.values())
                if s > m:
                    mydrop = [n]
                    m = s
                elif s == m:
                    mydrop.append(n)
            assert len(mydrop) > 0
            #plpy.notice('mydrop0: %s' % mydrop)
            
            # if there are ties, they are not just dropped but
            # replaced by the mid point of subgraphs
            # replacement may come as a chunk, so need to look into connectedness
            sg = cc.subgraph(mydrop)
            myrepl = [_ for _ in list(nx.connected_components(sg)) if len(_) > 1]
            torepl.extend(myrepl)
            
            # replacing nodes (filling node) still can be too close to other points, 
            # so need to included into the graph for further testing
            for repl in myrepl:
                # get list of neighbors
                newnbr = {}
                for n in repl:
                    for nbr in cc.neighbors(n):
                        if nbr in repl: continue
                        newnbr[nbr] = max(newnbr.get(nbr,0), cc.get_edge_data(n, nbr)['invdist'])
                # add place-holder
                if newnbr:
                    iadd -= 1
                    for nbr,idst in newnbr.items():
                        cc.add_edge(iadd, nbr, invdist=idst)
                    added[iadd] = repl

            # remove nodes
            #plpy.notice('mydrop: %s' % mydrop)
            #plpy.notice('myrepl: %s' % myrepl)
            todrop.extend(mydrop)
            cc.remove_nodes_from(mydrop)

    #plpy.notice('todrop: %s' % todrop)
    #plpy.notice('torepl: %s' % torepl)

    # if added node is later dropped, the replacement node shouldn''t be injected
    for idrp in todrop:
        if idrp >= 0: continue
        torepl.remove(added[idrp])

    # utility function to decipher torepl list
    def getorig(ns):
        # recursively find original nodes from added node
        lst = []
        for n in ns:
            if n >= 0:
                lst.append(n)
            else:
                lst.extend(getorig(added[n]))
        return lst

    torepl2 = {}
    for repl in torepl:
        myorig = getorig(repl)
        mymin = min(myorig)
        torepl2[mymin] = [_ for _ in myorig if _ != mymin]
    others = [torepl2.get(_, []) for _ in todrop]
    #plpy.notice(todrop)
    #plpy.notice(others)                    
    return zip(todrop,others)
        
$$ 
language plpython3u immutable;
-- language plpython2u volatile;
-- language plpythonu volatile;

-----------------------------------------------
-- Part 2.3: st_voronoi_py (voronoi polygon) --
-----------------------------------------------


drop type if exists list_of_polygon_coords cascade;
create type list_of_polygon_coords as (
-- type to be returned from python part of code
-- x, y are series of coordinate of vertices of one polygon region
-- pos tellis poition of input point.  need to remember position when getting out of python, because unnest() going to scramble the order  
	x float[],
	y float[],
	pos int  
);

create or replace function st_voronoi_python(x float[], y float[])
returns setof list_of_polygon_coords as
-- slave function using python.
-- as pl/python dont deal with complex data format, there need to be a middle man converting geomoetry to cooddinates.
$$
    import numpy as np
    from scipy.spatial import Voronoi

    # ref http://stackoverflow.com/questions/20515554/colorize-voronoi-diagram/20678647#20678647
    def voronoi_finite_polygons_2d(vor, radius=None):
        """
        Reconstruct infinite voronoi regions in a 2D diagram to finite
        regions.

        Parameters
        ----------
        vor : Voronoi
            Input diagram
        radius : float, optional
            Distance to 'points at infinity'.

        Returns
        -------
        regions : list of tuples
            Indices of vertices in each revised Voronoi regions.
        vertices : list of tuples
            Coordinates for revised Voronoi vertices. Same as coordinates
            of input vertices, with 'points at infinity' appended to the
            end.

        """
    
    
        new_regions = []
        new_vertices = vor.vertices.tolist()
    
        center = vor.points.mean(axis=0)
        if radius is None:

            radius = vor.points.ptp(axis=0).max() * 3
    
        # construct a map containing all ridges for a given point
        all_ridges = {}
        for (p1, p2), (v1, v2) in zip(vor.ridge_points, vor.ridge_vertices):
            all_ridges.setdefault(p1, []).append((p2, v1, v2))
            all_ridges.setdefault(p2, []).append((p1, v1, v2))
    
        # reconstruct infinite regions
        for p1, region in enumerate(vor.point_region):
            vertices = vor.regions[region]
    
            if all( v >= 0 for v in vertices):
                # finite region
                new_regions.append(vertices)
                continue
    
            # reconstruct an infinite region
            ridges = all_ridges[p1]
            new_region = [v for v in vertices if v >= 0]
    
            for p2, v1, v2 in ridges:
                if v2 < 0:
                    v1, v2 = v2, v1
                if v1 >= 0:
                    continue
    
                # compute the missing end point of an infinite ridge
    
                t = vor.points[p2] - vor.points[p1] # tangent
                t /= np.linalg.norm(t)
                n = np.array([-t[1], t[0]]) # normal
    
                midpoint = vor.points[[p1, p2]].mean(axis=0)
                direction = np.sign(np.dot(midpoint - center, n)) * n
                far_point = vor.vertices[v2] + direction * radius

                new_region.append(len(new_vertices))
                new_vertices.append(far_point.tolist())

            # sort region counter clockwise
            vs = np.asarray([new_vertices[v] for v in new_region])
            c = vs.mean(axis=0)
            angles = np.arctan2(vs[:,1] - c[1], vs[:,0] - c[0])
            new_region = np.array(new_region)[np.argsort(angles)]

            # finish
            new_regions.append(new_region.tolist())
            
        return new_regions, np.asarray(new_vertices)

    

    # start processing
    pnts = np.array([x,y]).T
    #plpy.notice('pnts: \n%s' % pnts)

    # add dummy points
    center = pnts.mean(axis=0)
    radius = pnts.ptp(axis=0).max() * 3
    dummys = np.tile(center, 4).reshape((4,2)) + radius * np.array([[1,1],[1,-1],[-1,-1],[-1,1]])
    pnts2 = np.vstack((pnts, dummys))
    #plpy.notice('pnts2: \n%s' % pnts2)
    
    # get voronoi diagram
    try:
        #vor = Voronoi(np.array([x, y]).T, qhull_options='QJ Pp')  
        vor = Voronoi(pnts2, qhull_options='QJ Pp')  
        # QJ
        #   always use joggle option to avoild coplaner problem
        #   => actually www.qhull.org says QJ is deplicated... but it works good for me
        # Pp 
        # suppress waringings
        #   The initial hull is narrow (cosine of min. angle is 1.0000000000000000).
        #    Is the input lower dimensional (e.g., on a plane in 3-d)?  Qhull may
        #    produce a wide facet.  Options 'QbB' (scale to unit box) or 'Qbb' (scale
        #    last coordinate) may remove this warning.  Use 'Pp' to skip this warning.
        #    See 'Limitations' in qh-impre.htm.
    except RuntimeError as e:
        #plpy.notice('a: \n%s' % np.array([x,y]).T)
        plpy.notice('a: \n%s' % np.array(pnts2))
        raise e
#    plpy.notice('points: %s' % vor.points)
#    plpy.notice('point region: %s' % vor.point_region)
#    plpy.notice('orig regions: %s' % vor.regions)

    regions, vertices = voronoi_finite_polygons_2d(vor)
#    plpy.notice('new regions: %s' % regions)
    #plpy.notice(vertices)
    assert len(regions) == len(pnts2)
    lst = []
    for i,reg in enumerate(regions):
        reg.append(reg[0])
        v = vertices[reg]
        lst.append([v[:,_].tolist() for _ in (0,1)] + [i+1] )
    return lst[:-4]

$$ 
language plpython3u immutable;
-- language plpython2u volatile;
-- language plpythonu volatile;


create or replace function st_voronoi_py(pnts geometry)
returns geometry as
$$
-- this is the middle man, taking geometry of points and returning polygons of voronoi.
-- wish i could make this into group function to take rows of points to return rows of geometry, but only PL/C can do.
-- so work around is that user is going to aggregate set of points into multipoints, and then call this function.
-- the user then break multipolygons back to points.  (st_collect() on points, and then st_dump() on returned multipolygon)
--select st_collect(geom) from (
with foo as (
	select (st_dump(pnts)).geom
)
, bar as (
	select array_agg(st_x(geom)) x, array_agg(st_y(geom)) y
	from foo
)
, baz as (
	select st_voronoi_python(x,y) coords
	from bar
)
, qux as (
	select unnest((baz.coords).x) x, unnest((baz.coords).y) y,  (baz.coords).pos idx
	from baz
)
, boz as (
	select st_point(x,y) geom, idx 
	from qux
)
, thud as (
	select st_makevalid(st_makepolygon(st_makeline(geom))) geom
	from boz
	group by idx order by idx
)
select st_setsrid(st_collect(geom), st_srid(pnts)) 
--select geom
from thud;
$$
language sql immutable;


---------------------------------------------
-- Part 2.4: st_cutter_py (cutter polygon) --
---------------------------------------------


create or replace function st_cutter_python(x float[], y float[])
returns setof list_of_polygon_coords as
$$ 
    import numpy as np
    np.seterr(all='raise')
    cas = 'x'
    #plpy.notice('xy: %s', [(p,q) for p,q in zip(x,y)])
    p = np.array([x, y]).T
    #radius = p.ptp(axis=0).max() 
    #radius = min(p.ptp(axis=0).max() , 1)  # 1 degree should be large enough 
    radius = p.ptp(axis=0).max() * 3 
    if len(p) == 2:
        cas = '2'
        #plpy.notice("p: %s" % p)
 
        # mid point
        midpoint = p.mean(axis=0)
        # tangent
        t = (p[1] - p[0])
        t /= np.linalg.norm(t)
        # normal
        normal = np.array([-t[1],t[0]])
        #plpy.notice("midpnt: %s" % midpoint)
        #plpy.notice("normal: %s" % normal)
        #plpy.notice("radius: %s" % radius)
        far_points = np.array([midpoint + normal*radius, midpoint - normal*radius, midpoint + t*radius, midpoint - t*radius])
        #plpy.notice("farpnt: %s" % far_points)
        lst = []
        lst.append(  ([far_points[(0,1,2,0),_].tolist() for _ in (0,1)] + [1] ) )
        lst.append(  ([far_points[(0,1,3,0),_].tolist() for _ in (0,1)] + [2] ) )
        #plpy.notice("lst: %s" % lst)
        #raise 
    elif len(x) == 3:
        cas = '3'
        # get length of each sides
        p0 = p
        p1 = np.roll(p, 1, axis=0)
        p2 = np.roll(p, 2, axis=0)
        # l, length of oposite side
        l = np.sqrt(((p1 - p2)**2).sum(axis=1))
        #plpy.notice("p: %s" % p)
        #plpy.notice("p1: %s" % p1)
        #plpy.notice("p2: %s" % p2)
        #plpy.notice("p12: %s" % (p1-p2))
        #plpy.notice("l: %s" % l)

        # move opposite corner of longest side as origin, and roll the point so that the corner is q[0]
        am = l.argmax()
        #plpy.notice("am: %s" % am)
        shft = p[am]
        #plpy.notice("shft: %s" % np.tile(shft,(3,1)))
        q0 = p - np.tile(shft,(3,1))
        #plpy.notice("q0: %s" % q0)
        q = np.roll(q0, -am, axis= 0)
        #plpy.notice("q: %s" % q)
        idx = np.roll(np.array([1,2,3]), -am)
        #plpy.notice("idx: %s" % q)

        cos = np.dot(q[1], q[2]) / np.linalg.norm(q[1])/np.linalg.norm(q[2])
        #plpy.notice("cos: %s" % cos)

        if cos < -.999 or cos > .999:
            # colinear
            cas = '3l'
            lst = []
            n = []
            far_points0 = []
            for i in 1,2:
                #plpy.notice("i: %s" % i)
                midpoint = .5*(q[0]+q[i])+shft
                t = (q[i]-q[0])
                #plpy.notice("t: %s" % t)
                t /= np.linalg.norm(t)
                #plpy.notice("t: %s" % t)
                normal = np.array([-t[1],t[0]])
                #plpy.notice("nrm: %s" % normal)
                far_points = np.array([midpoint+t*radius, midpoint+normal*radius, midpoint-normal*radius, midpoint+t*radius])
                far_points0.extend([midpoint+normal*radius, midpoint-normal*radius])
                #plpy.notice("fpt: %s" % far_points)
                lst.append(        ( [far_points[:,_].tolist() for _ in (0,1)] + [idx[i]] ) )
                n.append(normal) 
            #plpy.notice("far_points0: %s" % far_points0)
            far_points0 = far_points0 + [ far_points0[0]]
            #plpy.notice("far_points0: %s" % far_points0)
            lst.append( ( [np.array(far_points0)[:,_].tolist() for _ in (0,1)] + [idx[0]] ) )
            #plpy.notice("lst: %s" % lst)
        else:

             

            # https://en.wikipedia.org/wiki/Circumscribed_circle#Cartesian_coordinates_from_cross-_and_dot-products
            if np.cross( - q[1], q[1] - q[2] ) == 0:
                plpy.notice("l: %s" % l)
                plpy.notice("p: %s" % p)
                plpy.notice("am: %s" % am)
                plpy.notice("shft: %s" % shft)
                plpy.notice("q0: %s" % q0)
                plpy.notice("q: %s" % q)
                plpy.notice("cos: %s" % ( np.dot(q[1], q[2]) / np.linalg.norm(q[1])/np.linalg.norm(q[2]) ))
            try:
                denom = .5 / ((np.cross( - q[1], q[1] - q[2] ))**2 ).sum()
            except RuntimeError as e:
                plpy.notice("cos: %s" % ( np.dot(q[1], q[2]) / np.linalg.norm(q[1])/np.linalg.norm(q[1]) ))
                raise e
            beta  = (q[2]**2).sum() *  np.dot( q[1], q[1] - q[2] ) * denom 
            gamma = (q[1]**2).sum() *  np.dot( q[2], q[2] - q[1] ) * denom
            #plpy.notice("d,b,g: %s,%s,%s" % (denom, beta, gamma))
            center = beta * q[1] + gamma * q[2] 
            #plpy.notice("center: %s" % center)
    
            center0 = center + shft
            is_obtuse = False
            far_points0 = []
            side_points0 = []
    
            # draw three lays from circumcenter
            for i in range(3):
                if i == 0:
                    midpoint = .5 * (q[1] + q[2])
                    if abs(cos) < .0001: # ~right angle
                        direction = center # direction from corner of right angle, located at origin, to circum center
                        direction = direction / np.linalg.norm(direction)
                        cas = '3r'
                    else:
                        direction = midpoint - center
                        direction = direction / np.linalg.norm(direction)
                        if cos < 0: # obtuse
                            is_obtuse = True
                            direction = -direction
                            pp = np.append(q, center).reshape((-1,2))
                            #plpy.notice('pp: %s' % pp)
                            radius = pp.ptp(axis=0).max() * 3
                            side_point = center 
                            cas = '3o'
                else:
                    # mid point
                    midpoint = .5 * (q[i] + q[0])
                    direction = midpoint - center
                    direction = direction / np.linalg.norm(direction)
                #if np.linalg.norm(direction) == 0:
                #    plpy.notice("i, q: %s, %s" % (i, q))
                #    plpy.notice("m, c: %s, %s" % (midpoint, center))
                #    plpy.notice("d: %s" % np.dot(q[1], q[2]))
                #    plpy.notice("yyyy")
                    if is_obtuse:
                        # add extra point stratching out to side
                        t = (q[i]-q[0])
                        t /= np.linalg.norm(t)
                        side_point = center + t * radius

                far_point = center + direction * radius
                #plpy.notice("m, d, f: %s, %s, %s" % (midpoint, direction, far_point))

                far_points0.append(  far_point + shft )
                if is_obtuse:
                    side_points0.append(side_point + shft)
    
    
            # generate triangles
            if is_obtuse:
                lst = [
                    [[center0[_], far_points0[1][_],                     far_points0[2][_],center0[_]] for _ in (0,1)] + [idx[0]],
                    [[center0[_], far_points0[2][_], side_points0[2][_], far_points0[0][_],center0[_]] for _ in (0,1)] + [idx[1]],
                    [[center0[_], far_points0[0][_], side_points0[1][_], far_points0[1][_],center0[_]] for _ in (0,1)] + [idx[2]],
                    ]
            else:
                lst = []
                for i in range(3):
                    lst.append([[center0[_],far_points0[(i+1) % 3][_],far_points0[(i+2) % 3][_],center0[_]] for _ in (0,1)] + [idx[i]])
            #plpy.notice(lst)
            #raise
            #plpy.notice("lst: %s" % lst)
    
    else:
        raise RuntimeError("works only with 2 or 3 pnts")
        #plpy.notice("cas,lst: %s,%s" % (cas,lst))
    return lst
$$
language plpython3u immutable;
-- language plpython2u volatile;
-- language plpythonu volatile;

create or replace function st_cutter_py(pnts geometry)
returns geometry as
$$
with foo as  (
	select (st_dump(pnts)).geom
)
, bar as ( 
	select array_agg(st_x(geom)) x, array_agg(st_y(geom)) y 
	from foo 
)
, baz as (
	select st_cutter_python(x, y) coords
	from bar
)
, qux as (
	select unnest((baz.coords).x) x, unnest((baz.coords).y) y, (baz.coords).pos idx 
	from baz
)
, boz as (
	select st_point(x, y) geom, idx 
	from qux
)
, thud as ( 
	select st_makevalid(st_makepolygon(st_makeline(geom))) as geom
	from boz
	group by idx order by idx
)
select st_setsrid(st_collect(geom), st_srid(pnts))
from thud;
$$
language sql immutable;



---------------------------------------------------------------------
-- Part 2.5: st_polsbypopper (Polsby-Popper measure of elongation) --
---------------------------------------------------------------------

-- function to determine elongation.  circle == 1, square = 0.78, equilateral triagle = 0.6, approaches 0 as elongates
-- arbitrary defined that null geometry has 0 value
create or replace function st_polsbypopper(geom geometry)
returns double precision as
$$
with foo as (
	select geom, st_area(geom) as a, st_perimeter(geom) as p
) 
select 
case 
when a = 0 then 0
else 4 * pi() * a / (p * p)
end
from foo;
$$
language sql immutable;

create or replace function st_polsbypopper(geom geometry, use_spheroid boolean)
returns double precision as
$$
with foo as (
	select geom, st_area(geom, use_spheroid) as a, st_perimeter(geom, use_spheroid) as p
) 
select 
case 
when a = 0 then 0
else 4 * pi() * a / (p * p)
end
from foo;
$$
language sql immutable;

---------------------------------------------------
-- Part 2.7: get_acq_datetime (local solar time) --
---------------------------------------------------

create or replace function get_acq_datetime_lst(acq_date_utc date, acq_time_utc character, longitude double precision)
returns timestamp without time zone as
$$
with foo as ( select acq_date_utc, acq_time_utc, longitude)
select cast(acq_date_utc as timestamp without time zone) +
        make_interval( hours:= substring(acq_time_utc, 1, 2)::int + round(longitude / 15)::int,
          mins:= substring(acq_time_utc from '^\d\d:?(\d\d)')::int)
          from foo;

$$
language sql immutable;

create or replace function get_acq_datetime_lst(acq_date_utc date, acq_time_utc time without time zone, longitude double precision)
returns timestamp without time zone as
$$
with foo as ( select acq_date_utc, acq_time_utc, longitude)
select  cast(acq_date_utc as timestamp without time zone) +
        acq_time_utc +
        make_interval( hours:=  round(longitude / 15)::int)
          from foo;

$$
language sql immutable;

create or replace function time_to_char(acq_time character)
returns character as
$$
-- get rid of : in the middle if there is, stick with old format
select substring(acq_time from '^\d\d:?(\d\d)');
$$
language sql immutable;

create or replace function time_to_char(acq_time time without time zone)
returns character as
$$
select to_char(acq_time, 'HH24MI');
$$
language sql immutable;

--------------------------
-- Part 2.8: instrument --
--------------------------
--       case left(satellite,1) when ''T'' then ''MODIS'' when ''A'' then ''MODIS'' when ''N'' then ''VIIRS'' else null end,
create or replace function get_instrument(satellite character)
returns character as
$$
select case left(satellite, 1)
when 'T' then 'MODIS'
when 'A' then 'MODIS'
when 'N' then 'VIIRS'
else null
end;
$$
language sql immutable;

-- viirs file has 'N', and OGR may treat it as boolean no, seems like.  so interpret false as viirs
create or replace function get_instrument(satellite boolean)
returns character as
$$
select case satellite
when TRUE then null
when FALSE then 'VIIRS'
end;
$$
language sql immutable;

-----------------------------------
-- Part 3: Start processing data --
-----------------------------------

-- find af_in tables (names)
-- also see if "type" field is available
-- seems like sometime between fall 2018 and spring 2019, AF folks introduced daynight and type field


drop table if exists af_ins;
create table af_ins as (
  select table_name, FALSE has_type 
  from information_schema.tables 
  where table_schema = :quote_myschema);

update  af_ins a set has_type = foo.chk
from (
  select i.table_name, bool_or(i.column_name = 'type') chk 
  from information_schema.columns  i
  where i.table_schema = :quote_myschema
  group by table_name
) foo 
where foo.table_name = a.table_name;

DO LANGUAGE plpgsql $$ 
  DECLARE 
    any_has_type boolean;
  BEGIN
    any_has_type := (
      SELECT bool_or(has_type) 
      FROM af_ins
    );

    IF NOT any_has_type THEN
      UPDATE tbl_options
      SET opt_value = 'false'
      WHERE opt_name = 'filter_persistent_sources';
    END IF;
END $$;

do language plpgsql $$ begin 
  if (select count(*) from af_ins where table_name = 'af_in') = 1 then 
    delete from af_ins where table_name != 'af_in'; 
  else 
    delete from af_ins where  table_name !~ 'af_in_[0-9]'; 
  end if ; 
end $$;


do language plpgsql $$ begin
raise notice 'tool: processing start, %', clock_timestamp();
raise notice 'tool: start importing, %', clock_timestamp();
end $$;

do language plpgsql $$ 
  declare 
    myrow record; 
    s varchar; 
    i bigint;
  begin

    for myrow in select table_name,has_type from af_ins order by table_name loop 
      raise notice 'tool: myrow , %', myrow; 

      s := 'insert into work_pnt  (rawid, geom_pnt, lon, lat, scan, track, acq_date_utc, acq_time_utc, acq_date_lst, acq_datetime_lst, instrument, confident, anomtype) select 
      row_number()  over (order by gid), 
      geom, 
      longitude, 
      latitude, 
      scan, 
      track, 
      acq_date, 
      time_to_char(acq_time),
      date(get_acq_datetime_lst(acq_date, acq_time, longitude)),
      get_acq_datetime_lst(acq_date, acq_time, longitude),
      get_instrument(satellite),
      case get_instrument(satellite) when ''MODIS'' then confidence::integer >= 20 when ''VIIRS'' then confidence::character(1) != ''l'' end , ' ||
      case myrow.has_type WHEN TRUE THEN ' type ' ELSE ' 0 ' END ||
      ' from ' || myrow.table_name || ';'; 

      raise notice 's: %', s; 
      i := log_checkin('import ' || myrow.table_name, 'work_pnt', (select count(*) from work_pnt));
      execute s; 
      i := log_checkout(i, (select count(*) from work_pnt) );
    end loop;
end $$;

do language plpgsql $$ begin
raise notice 'tool: import done, %', clock_timestamp();
end $$;

-- drop by date
DO LANGUAGE plpgsql $$
  declare
    i bigint;
    rng daterange;
  begin
    rng := (select opt_value::daterange FROM tbl_options WHERE opt_name = 'date_range');
    if rng <> '[,]'::daterange  then
      raise notice 'tool: rng, %', rng;

      i := log_checkin('drop detes of no interest', 'work_pnt', (select count(*) from work_pnt)); 
      delete from work_pnt
      where not (acq_date_lst <@ rng);
      i := log_checkout(i, (select count(*) from work_pnt)); 
      raise notice 'tool: dropping dates of no interest done, %', clock_timestamp(); 
    else
      raise notice 'tool: no dates of interst defined';
    end if;
  end
$$;


-- drop low confidence points
DO LANGUAGE plpgsql $$
  declare
    i bigint;
  begin
    i := log_checkin('drop low confience', 'work_pnt', (select count(*) from work_pnt)); 
    delete from work_pnt 
    where not confident;
    i := log_checkout(i, (select count(*) from work_pnt) );
  END
  $$;

do language plpgsql $$ begin
raise notice 'tool: dropping low condifence done, %', clock_timestamp();
end $$;

DO LANGUAGE plpgsql $$ 
  DECLARE
    filter_persistent_sources boolean;
    i bigint;
  BEGIN 
    -- only when filter_persistent_sources is True, 
    -- drop volcano and "other" anomaly (not vegetation burn) 
    filter_persistent_sources := (
      SELECT opt_value 
      FROM tbl_options 
      WHERE opt_name = 'filter_persistent_sources'
    ); 
    
    IF filter_persistent_sources THEN 
      i := log_checkin('drop persistent', 'work_pnt', (select count(*) from work_pnt)); 
      DELETE FROM work_pnt 
      WHERE anomtype = 1 OR anomtype = 2; 
      i := log_checkout(i, (select count(*) from work_pnt) );

      raise notice 'tool: dropping volcano/other persistent done, %', clock_timestamp(); 
    ELSE 
      raise notice 'tool: no special treatment for volcano/other persistent';
    END IF; 
  END 
$$;


-- dup tropics
DO LANGUAGE plpgsql $$ 
  DECLARE
    i bigint;
  BEGIN 
    i := log_checkin('dup tropics', 'work_pnt', (select count(*) from work_pnt)); 
    insert into work_pnt (rawid, geom_pnt, lon, lat, scan, track, acq_date_utc, acq_time_utc, acq_date_lst, acq_datetime_lst, instrument, confident, anomtype)
    select rawid, geom_pnt, lon, lat, scan, track, acq_date_utc + 1, acq_time_utc, acq_date_lst + 1, acq_datetime_lst + interval '1 day', instrument, confident, anomtype from work_pnt
    where abs(lat) <= 23.5 and instrument = 'MODIS';
    i := log_checkout(i, (select count(*) from work_pnt) );
  END;
$$;
do language plpgsql $$ begin
raise notice 'tool: duplicating tropics done, %', clock_timestamp();
end $$;

-- pk
alter table work_pnt add column cleanid serial;
alter table work_pnt add primary key(cleanid);

do language plpgsql $$ begin
raise notice 'tool: indexing done, %', clock_timestamp();
end $$;
