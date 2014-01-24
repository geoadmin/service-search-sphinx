#!/usr/bin/env python
# -*- coding: utf-8 -*-
# 
# read sphinx config file and update all indexes related to input database or input table

# parameter
# -db:      (optional)      database filter:
#                           p.e. 
#                           -db are all sphinx indexes from database x
#                           -db are.siedlung_landschaft all sphinx indexes from schema x in database y
#                           -db are.siedlung_landschaft.landschaftstypen all indexes from table x
#                           if parameter is missing, all the sphinx indexes are listed or updated!!
#
# -list:    (default)       list sphinx indexes, nothing happens with the existing indexes
# -update:                  update sphinx indexes
#                           the indexes are updated with the sphinx indexer using the following command:
#                           indexer --verbose --sighup-each --rotate <<index>>
#
# Examples:
#   1) list all indexes which are based on database stopo
#   $ python pg2sphinx_trigger.py -db stopo -list
#
#   2) update all indexes which are based on database search
#   $ python pg2sphinx_trigger.py -db search -update
#
#

import os
import sys
import time
import getpass
import re
import sqlite3
import pprint
import psycopg2
import optparse
import subprocess
from optparse import OptionParser


def pg_get_tables(sql_query,sql_db):
    # add 'EXPLAIN VERBOSE ' to sql string
    sql_query = 'EXPLAIN VERBOSE ' + sql_query

    conn_string = "host='%s' dbname='%s' user='%s' password='%s'" % (CONN_HOST,sql_db,CONN_USER,CONN_PWD)
    # get a connection, if a connect cannot be made an exception will be raised here
    conn = psycopg2.connect(conn_string)
    # conn.cursor will return a cursor object, you can use this cursor to perform queries
    cursor = conn.cursor()
    # execute our Query
    cursor.execute(sql_query)
    # retrieve the records from the database
    records = cursor.fetchall()
    t = []
    for i in records:
        table = re.search('[Bitmap Heap|Index|Seq] Scan.* on ([^ ]+)', i[0])
        table = table.group(1) if table else None
        if table and not 'Bitmap Index Scan' in i[0]: 
            t.append(sql_db+'.'+table)
            #print "linie: '%s' -> extract: '%s'" % (i[0],table)
    t = list(set(t)) # get rid of duplicate entries in the list and sorting
    return  ','.join(sorted(t))


if __name__ == '__main__':
    SPHINXCONFIG="/etc/sphinxsearch/sphinx.conf"
    USER="sphinxsearch"
    myenv = dict(os.environ)

    ################################
    # Command Line Argument Parsing
    ################################

    epilog = """Examples:
    1) list all indexes which are based on database stopo:
    python pg2sphinx_trigger.py -d stopo -c list

    2) list all indexes which are based on database stopo schema vd:
    python pg2sphinx_trigger.py -d stopo.vd -c list

    3) update all indexes which are based on database search:
    python pg2sphinx_trigger.py -d search -c update

    4) update all indexes which are based on table search.public.swisssearch:
    python pg2sphinx_trigger.py -d search.public.swiss_search -c update

    5) update all the indexes using a custom config file:
    python pg2sphinx_trigger.py -c update -s /path/to/my/sphinx.conf
    \n"""

    OptionParser.format_epilog = lambda self, formatter: self.epilog
    parser = OptionParser(epilog=epilog)
    parser.add_option("-d","--database_filter", dest="filter", default=None, action="store", help="Database Filter: optional database praefix")
    parser.add_option("-c","--command", dest="command", default=str('list'), action="store", help="-c list: will list all the indexes touched by the database filter\n-c update will update all the indexes touched by the database filter.")
    parser.add_option("-s","--sphinxconf", dest="config", default=SPHINXCONFIG, action="store", help="-s /path/to/sphinx/sphinx.conf")
    (options, args) = parser.parse_args()

    # Some initial tests
    if not getpass.getuser() == USER:
        sys.exit("ERROR: Script has to be executed with user %s, you are executing the script with %s"  % (USER,getpass.getuser()) )

    if not os.path.isfile(options.config):
        sys.exit("ERROR: Sphinx Config could not be opened: %s" % options.config)

    # -c --command
    if options.command not in ['list','update']:
        parser.print_help()
        sys.exit( 1 )

    # SQLITE Initialize and create tables in memory    
    conn = sqlite3.connect(":memory:")
    c = conn.cursor()
    c.execute("create table sources (id INTEGER PRIMARY KEY, source text, source_parent text, sql_db text, sql_query text, indexes text);")
    c.execute("create table indexes (id INTEGER PRIMARY KEY, sphinx_index text, index_parent, source text);")
    # switch to sqlite3 dictionary mode
    c.row_factory = sqlite3.Row

    # Read Sphinx Config
    with open (SPHINXCONFIG, "r") as myfile:
        data=myfile.read()

    # Parse PG Connection from Sphinx Config
    CONN_HOST=re.findall('sql_host\s=\s(.*)', data)[0]
    CONN_USER=re.findall('sql_user\s=\s(.*)', data)[0]
    CONN_PWD=re.findall('sql_pass\s=\s(.*)', data)[0]
    CONN_PORT=re.findall('sql_port\s=\s(.*)', data)[0]


    # parse sphinx config sources and write them to sqlite sources table ...
    # TODO: 
    # regex which can extract source, sql_db and sql_query in one step
    # step 1 extract source and content in curly braces
    reg_source = re.compile(r'''
            ^
            source\s+                           # source start
            (?P<source>[^\n]+)                  # catch source group
            .*?                                 # Next part:
            (?P<content> (?<={)[^}]*(?=}))      # catch everything but curly braces
        ''', re.MULTILINE | re.DOTALL | re.VERBOSE)

    for i in reg_source.finditer(data):
        tmp_source = i.groupdict()['source'].split(':')
        source_parent = tmp_source[1] if len(tmp_source)>1 else None
        source = tmp_source[0]
        # step 2 extract sql_db and sql_query from curly braced content
        sql_db = re.search('sql_db\s=\s([\w]+)', i.groupdict()['content'])
        sql_db = sql_db.group(1) if sql_db else None

        sql_query = re.findall('^\s+sql_query\s=(.*)$', i.groupdict()['content'], re.MULTILINE | re.DOTALL | re.VERBOSE)
        sql_query = sql_query[0].replace('\\','').replace('\n', '').strip() if sql_query else None

        c.execute("INSERT INTO sources (source,source_parent,sql_db,sql_query) VALUES(? ,?, ?, ?);" ,(unicode(source.strip(),'UTF-8'), unicode(str(source_parent).strip(),'UTF-8'), sql_db, sql_query))

    # parse sphinx config indexes and write them to sqlite indexes table ...
    # TODO: 
    # regex which can extract source, sql_db and sql_query in one step
    # step 1 extract source and content in curly braces
    reg_index = re.compile(r'''
            ^
            index\s+                            # index start
            (?P<index>[^\n]+)                   # catch indexgroup
            .*?                                 # Next part:
            (?P<content> (?<={)[^}]*(?=}))      # catch everything but curly braces
        ''', re.MULTILINE | re.DOTALL | re.VERBOSE)

    for i in reg_index.finditer(data):
        tmp_index = i.groupdict()['index'].split(':')
        index_parent = tmp_index[1] if len(tmp_index)>1 else None
        index = tmp_index[0]
        # step 2 extract sql_db and sql_query from curly braced content
        source = re.search('source\s=\s(.*)', i.groupdict()['content'])
        source = source.group(1) if source else None
        if not ( source is None and index_parent is None ):
            c.execute("INSERT INTO indexes (sphinx_index, index_parent,source) VALUES(?, ?, ?);" ,(unicode(index.strip(),'UTF-8'), unicode(str(index_parent).strip()), source))

    # output

    sql = """
    select
        a.source as source
        , coalesce(a.sql_db,b.sql_db) as database
        , a.sql_query as sql
        , group_concat(i.sphinx_index,' ') as sphinx_index
        FROM 
        indexes i left join indexes p on trim(i.index_parent)=trim(p.sphinx_index)
        left join sources a on coalesce(i.source,p.source) = a.source
        left join sources b on a.source_parent = b.source
        group by a.source,  coalesce(a.sql_db,b.sql_db)
    """

    resultat=[]
    for row in c.execute(sql):
        # db only filter can be applied to sphinx config, no need to query postgres db
        if (options.filter and options.filter.count('.')==0) or (options.filter == None):
            # db only filter can be applied to sphinx config, no need to query postgres db
            if (options.filter==row['database']) or (options.filter == None):
                if options.command=='list':
                    for test in row['sphinx_index'].split(' '):
                        resultat.append("%s -> %s" % (test,row['database'] ))
                else:
                    resultat.append("%s" % (row['sphinx_index']))
        elif options.filter.split(".")[0]==row['database']:
            if options.filter in pg_get_tables(row['sql'],row['database']):
                if options.command=='list':
                    for test in row['sphinx_index'].split(' '):
                        resultat.append("%s -> %s" % (test,pg_get_tables(row['sql'],row['database'] ) ))
                else:
                    resultat.append("%s" % (row['sphinx_index']))

    resultat = sorted(list(set(resultat))) # get rid of duplicate entries in the list and sorting   
    indent="\n      "     
    if options.command == 'list':
        if resultat:
            print "%s indexes are using the database pattern: %s%s%s" % (len(resultat), options.filter,indent,indent.join(resultat))
        else:
            print "no indexes are using the database pattern: %s" % (options.filter)
    elif options.command == 'update':
        if resultat:
            sphinx_command = 'indexer --config %s --verbose --rotate --sighup-each %s' % (options.config,' '.join(resultat))
            print sphinx_command
            #uncomment following lines for real update
            p = subprocess.Popen(sphinx_command,stdout=subprocess.PIPE,shell=True, env=myenv)
            for line in iter(p.stdout.readline, ''):
                print line.strip()
            p.stdout.close()
            
        else:
            print 'no sphinx indexes are using the database pattern %s.' % (options.filter)

#
# $Id$
#
