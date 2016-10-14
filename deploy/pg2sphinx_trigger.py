#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# read sphinx config file and update all indexes related to input database or input table or index pattern

import os
import sys
import time
import getpass
import re
import sqlite3
import psycopg2
import optparse
import subprocess
from optparse import OptionParser


def pg_get_tables(sql_query, sql_db):
    # add 'EXPLAIN VERBOSE ' to sql string
    sql_query = 'EXPLAIN VERBOSE ' + sql_query

    conn_string = "host='%s' dbname='%s' user='%s' password='%s'" % (CONN_HOST, sql_db, CONN_USER, CONN_PWD)
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
    Indexes can be filtered by database pattern (-d) or by index pattern (-i)

    1) list all indexes which are based on database stopo:
    python pg2sphinx_trigger.py -d stopo_prod -c list

    2) list all indexes which are based on database stopo schema vd:
    python pg2sphinx_trigger.py -d stopo_prod.vd -c list

    3) update all indexes which are based on database search:
    python pg2sphinx_trigger.py -d search_int -c update

    4) update all indexes which are based on table search.public.swisssearch:
    python pg2sphinx_trigger.py -d search_int.public.swiss_search -c update

    5) update all the indexes using a custom config file:
    python pg2sphinx_trigger.py -c update -s /path/to/my/sphinx.conf

    6) list all indexes with the prefix pattern ch_swisstopo_vec25
    python pg2sphinx_trigger.py -c list -i ch_swisstopo_vec25
    \n"""

    OptionParser.format_epilog = lambda self, formatter: self.epilog
    parser = OptionParser(epilog=epilog)
    parser.add_option("-d",
                      "--database_filter",
                      dest="database_filter",
                      default=None,
                      action="store",
                      help="Database Filter: optional database prefix")
    parser.add_option("-i",
                      "--index_filter",
                      dest="index_filter",
                      default=None,
                      action="store",
                      help="Index Filter: optional index prefix")
    parser.add_option("-c",
                      "--command",
                      dest="command",
                      default="list",
                      action="store",
                      help="-c list: will list all the indexes touched by the database filter\n-c update: will update all the indexes touched by the database filter.")
    parser.add_option("-s",
                      "--sphinxconf",
                      dest="config",
                      default=SPHINXCONFIG,
                      action="store",
                      help="-s /path/to/sphinx/sphinx.conf")
    (options, args) = parser.parse_args()

    # Some initial tests
    if not getpass.getuser() == USER:
        sys.exit("ERROR: Script has to be executed with user %s, you are executing the script with %s"  % (USER,getpass.getuser()) )

    if not os.path.isfile(options.config):
        sys.exit("ERROR: Sphinx config file doesn't exist: %s" % options.config)

    # -c --command
    if options.command not in ['list', 'update']:
        parser.print_help()
        sys.exit( 1 )

    # choose -d or -i
    if options.database_filter and options.index_filter:
        parser.print_help()
        sys.exit( 1 )

    filter_option = ""
    if options.database_filter:
        filter_option='database'

    if options.index_filter:
        filter_option='index'

    if options.config:
         SPHINXCONFIG=options.config


    # SQLITE Initialize and create tables in memory
    conn = sqlite3.connect(":memory:")
    c = conn.cursor()
    c.execute("""
                CREATE TABLE sources (
                    id INTEGER PRIMARY KEY
                    , source text
                    , source_parent text
                    , sql_db text
                    , sql_query text
                    , indexes
                    text
                    );
                    """)

    c.execute("""
                CREATE TABLE indexes (
                    id INTEGER PRIMARY KEY
                    , sphinx_index text
                    , index_parent
                    , source text
                    );
                    """)
    # switch to sqlite3 dictionary mode
    c.row_factory = sqlite3.Row

    # Read Sphinx Config
    with open (SPHINXCONFIG, "r") as myfile:
        data=myfile.read()

    # Parse PG Connection from Sphinx Config
    CONN_HOST=re.findall('sql_host\s*=\s*(.*)', data)[0]
    CONN_USER=re.findall('sql_user\s*=\s*(.*)', data)[0]
    CONN_PWD=re.findall('sql_pass\s*=\s*(.*)', data)[0]
    CONN_PORT=re.findall('sql_port\s*=\s*(.*)', data)[0]

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
        ''', re.MULTILINE | re.DOTALL | re.VERBOSE | re.UNICODE )

    # Parent : Child1  -> ('Parent', 'Child1')
    # Parent2: Child2  -> ('Parent2', 'Child2')
    # Parent           -> ('Parent', None)
    parsing_func = lambda x: [p.strip() for p in x.split(':')] if ':' in x else (x.strip(), None)
    for i in reg_source.finditer(data):
        source, source_parent = parsing_func(i.groupdict()['source'])
        # step 2 extract sql_db and sql_query from curly braced content
        sql_db = re.search('sql_db\s*=\s*([\w]+)', i.groupdict()['content'])
        sql_db = sql_db.group(1) if sql_db else None

        sql_query = re.findall('^\s+sql_query\s*=(.*)$', i.groupdict()['content'], re.MULTILINE | re.DOTALL | re.VERBOSE | re.UNICODE)
        sql_query = sql_query[0].replace('\\','').replace('\n', '').strip() if sql_query else None
        c.execute("""
                    INSERT INTO sources (
                        source
                        , source_parent
                        , sql_db
                        , sql_query
                        )
                        VALUES  (? ,?, ?, ?);""" ,(source.strip(), str(source_parent).strip(), sql_db, sql_query))

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
        ''', re.MULTILINE | re.DOTALL | re.VERBOSE | re.UNICODE)

    # get distributed indices first
    distributed_index = {}
    for i in reg_index.finditer(data):
        index, index_parent = parsing_func(i.groupdict()['index'])
        # distributed indexes
        index_type = re.search('type\s=\s*(.*)', i.groupdict()['content'])
        index_type = index_type.group(1).strip() if index_type else None
        index_local = re.findall('local\s=\s*(.*)', i.groupdict()['content'])
        index_local = index_local if index_local else None
        if index_local:
            distributed_index[index] = index_local

    for i in reg_index.finditer(data):
        index, index_parent = parsing_func(i.groupdict()['index'])
        # step 2 extract sql_db and sql_query from curly braced content
        source = re.search('source\s=\s*(.*)', i.groupdict()['content'])
        source = source.group(1).strip() if source else None
        # set index_parent to distributed_index if one exists otherwise index_parent is None
        index_parent = None
        for k,v in distributed_index.iteritems():
            if index in v:
                index_parent = k
        # import only real indexes, no distributed indexes
        if not ( source is None and index_parent is None ):
            c.execute("""
                        INSERT INTO indexes (
                            sphinx_index
                            , index_parent
                            , source
                            ) VALUES(?, ?, ?);""" ,(index.strip(), str(index_parent).strip(), source))

    # output
    sql = """
        SELECT
            a.source as source
            , coalesce(a.sql_db, b.sql_db) as database
            , a.sql_query as sql
            , i.sphinx_index
            , i.index_parent
            FROM
            indexes i LEFT JOIN indexes p on trim(i.index_parent) = trim(p.sphinx_index)
            LEFT JOIN sources a on coalesce(i.source, p.source) = a.source
            LEFT JOIN sources b on a.source_parent = b.source
    """

    tables_target = []
    db_path = options.database_filter.split('.')
    is_table_target = bool(re.match('^[a-z]+_(dev|int|prod)\.[a-z|_|0-9]+\.[a-z|_|0-9]+$', options.database_filter))
    if is_table_target:
        sql_target = 'SELECT * FROM %s.%s' % (db_path[1], db_path[2])
        try:
            tables_target = pg_get_tables(sql_target, db_path[0])
            tables_target = tables_target.split(',')
        except Exception as e:
            msg = 'Error while analysing table deps\n'
            msg += 'SQL: %s\n%s' % (sql, e)
            raise Exception(e)
        # Add initial view to the list
        if options.database_filter not in tables_target:
            tables_target.append(options.database_filter)
    results=[]
    for row in c.execute(sql):
        db = None
        indices = row['sphinx_index']
        indices_distributed = row['index_parent']
        # database filter
        # -d pattern
        if options.index_filter is None:
            if (options.database_filter and len(db_path) == 0) or (options.database_filter == None):
                # db only filter can be applied to sphinx config, no need to query postgres db
                if options.database_filter is None or options.database_filter == row['database']:
                    db = row['database']
                # if db filter is more detailed, we have to analyze the sql queries with postgres ANALZYE VERBOSE
            elif db_path[0] == row['database']:
                # In case the taget is table, only the SQL related to the target table for sphinx rotation indices
                if is_table_target:
                    tables = []
                    if len([t for t in tables_target if t.replace('%s.' % row['database'], '') in row['sql']]) > 0:
                        table_path = '%s.%s' % (db_path[1], db_path[2])
                        try:
                            tables =  pg_get_tables(row['sql'], row['database'])
                        except Exception as e:
                            msg = 'SQL query not valid for table %s\n' % table_path
                            msg += 'Trying to evaluate the following query:\n'
                            msg += '%s\n' % row['sql']
                            msg += 'Error:\n%s' % e
                            raise Exception(msg)
                        # we're dealing with a view
                        if options.database_filter not in tables:
                            tables += ',%s' % options.database_filter
                # Otherwise try all sql queries and bail out on any error
                else:
                    try:
                        tables =  pg_get_tables(row['sql'], row['database'])
                    except Exception as e:
                        msg = 'Trying to evaluate the following query:\n'
                        msg += '%s\n' % row['sql']
                        msg += 'Error:\n%s' % e
                        raise Exception(msg)
                db = row['database'] if options.database_filter in tables else None
        # indice filter
        # -i pattern
        else:
            if options.index_filter in indices or options.index_filter == 'all' or options.index_filter in indices_distributed:
                db = row['database']

        # output
        if options.command == 'list' and db is not None:
            results.append("%s -> %s" % (indices, db))

        if options.command == 'update' and db is not None:
            results.append("%s" % (indices))

    results = sorted(list(set(results))) # get rid of duplicate entries in the list and sorting
    indent="\n      "
    if options.command == 'list':
        if results:
            print "%s indexes are using the %s pattern: %s%s%s" % (len(results), filter_option, options.database_filter or options.index_filter, indent, indent.join(results))
        else:
            print "no indexes are using the %s pattern: %s" % (filter_option, options.database_filter or options.index_filter)
    elif options.command == 'update':
        if results:
            sphinx_command = 'indexer --config %s --verbose --rotate --sighup-each %s' % (options.config,' '.join(results))
            print sphinx_command
            #uncomment following lines for real update
            p = subprocess.Popen(sphinx_command, stdout=subprocess.PIPE, shell=True, env=myenv)
            for line in iter(p.stdout.readline, ''):
                print line.strip()
            p.stdout.close()
        else:
            print 'no sphinx indexes are using the %s pattern %s' % (filter_option, options.database_filter or options.index_filter)
