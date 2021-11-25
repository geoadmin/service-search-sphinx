#
# $Id$
#

import sys
import time

# import only used stuff
from sphinxapi import SPH_ATTR_TIMESTAMP
from sphinxapi import SPH_GROUPBY_ATTR
from sphinxapi import SPH_MATCH_ALL
from sphinxapi import SPH_MATCH_ANY
from sphinxapi import SPH_MATCH_BOOLEAN
from sphinxapi import SPH_MATCH_EXTENDED
from sphinxapi import SPH_SORT_EXTENDED
from sphinxapi import SphinxClient

if not sys.argv[1:]:
    print("Usage: python test.py [OPTIONS] query words\n")
    print("Options are:")
    print("-h, --host <HOST>\tconnect to searchd at host HOST")
    print("-p, --port\t\tconnect to searchd at port PORT")
    print("-i, --index <IDX>\tsearch through index(es) specified by IDX")
    print("-s, --sortby <EXPR>\tsort matches by 'EXPR'")
    print("-a, --any\t\tuse 'match any word' matching mode")
    print("-b, --boolean\t\tuse 'boolean query' matching mode")
    print("-e, --extended\t\tuse 'extended query' matching mode")
    print("-f, --filter <ATTR>\tfilter by attribute 'ATTR' (default is 'group_id')")
    print("-v, --value <VAL>\tadd VAL to allowed 'group_id' values list")
    print("-g, --groupby <EXPR>\tgroup matches by 'EXPR'")
    print("-gs,--groupsort <EXPR>\tsort groups by 'EXPR'")
    print("-l, --limit <COUNT>\tretrieve COUNT matches (default is 20)")
    print(
        "-ga, --geoanchor <LAT> <LON>\tsets GeoAnchor at given lat/lon (in minutes decimal). \
          Index must contain lat/lon attributes"
    )
    sys.exit(0)

q = ''
mode = SPH_MATCH_ALL
host = 'localhost'
port = 9312
index = '*'
filtercol = 'group_id'
filtervals = []
sortby = ''
groupby = ''
groupsort = '@group desc'
limit = 0
geoanchor = []

i = 1
while i < len(sys.argv):
    arg = sys.argv[i]
    if arg in ('-h', '--host'):
        i += 1
        host = sys.argv[i]
    elif arg in ('-p', '--port'):
        i += 1
        port = int(sys.argv[i])
    elif arg == '-i':
        i += 1
        index = sys.argv[i]
    elif arg == '-s':
        i += 1
        sortby = sys.argv[i]
    elif arg in ('-a', '--any'):
        mode = SPH_MATCH_ANY
    elif arg in ('-b', '--boolean'):
        mode = SPH_MATCH_BOOLEAN
    elif arg in ('-e', '--extended'):
        mode = SPH_MATCH_EXTENDED
    elif arg in ('-f', '--filter'):
        i += 1
        filtercol = sys.argv[i]
    elif arg in ('-v', '--value'):
        i += 1
        filtervals.append(int(sys.argv[i]))
    elif arg in ('-g', '--groupby'):
        i += 1
        groupby = sys.argv[i]
    elif arg in ('-gs', '--groupsort'):
        i += 1
        groupsort = sys.argv[i]
    elif arg in ('-l', '--limit'):
        i += 1
        limit = int(sys.argv[i])
    elif arg in ('-ga', '--geoanchor'):
        i += 1
        geoanchor.append(float(sys.argv[i]))
        i += 1
        geoanchor.append(float(sys.argv[i]))
    else:
        q = '%s%s ' % (q, arg)
    i += 1

# do query
cl = SphinxClient()
cl.SetConnectTimeout(5.)
cl.SetServer(host, port)
cl.SetMatchMode(mode)
if len(geoanchor) > 1:
    cl.SetGeoAnchor('lat', 'lon', geoanchor[0], geoanchor[1])
if filtervals:
    cl.SetFilter(filtercol, filtervals)
if groupby:
    cl.SetGroupBy(groupby, SPH_GROUPBY_ATTR, groupsort)
if sortby:
    cl.SetSortMode(SPH_SORT_EXTENDED, sortby)
if limit:
    cl.SetLimits(0, limit, max(limit, 1000))
res = cl.Query(q, index)

if not res:
    print('query failed: %s' % cl.GetLastError())
    sys.exit(1)

if cl.GetLastWarning():
    print('WARNING: %s\n' % cl.GetLastWarning())

print(
    'Query \'%s\' retrieved %d of %d matches in %s sec' %
    (q, res['total'], res['total_found'], res['time'])
)
print('Query stats:')

if 'words' in res:
    for info in res['words']:
        print(
            '\t\'%s\' found %d times in %d documents' % (info['word'], info['hits'], info['docs'])
        )

if 'matches' in res:
    n = 1
    print('\nMatches:')
    for match in res['matches']:
        attrsdump = ''
        for attr in res['attrs']:
            attrname = attr[0]
            attrtype = attr[1]
            value = match['attrs'][attrname]
            if attrtype == SPH_ATTR_TIMESTAMP:
                value = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(value))
            attrsdump = '%s, %s=%s' % (attrsdump, attrname, value)

        print('%d. doc_id=%s, weight=%d%s' % (n, match['id'], match['weight'], attrsdump))
        n += 1

#
# $Id$
#
