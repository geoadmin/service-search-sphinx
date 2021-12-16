#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# read sphinx config file and update all indexes related to input database or
# input table or index pattern

import argparse
import os
import re
import sqlite3
import subprocess
import sys

import psycopg2


def pg_get_tables(sql_query, sql_db):
    # add 'EXPLAIN VERBOSE ' to sql string
    sql_query = 'EXPLAIN VERBOSE ' + sql_query

    conn_string = f"host='{CONN_HOST}' dbname='{sql_db}' user='{CONN_USER}' password='{CONN_PWD}'"

    # get a connection, if a connect cannot be made an exception will be raised here
    conn = psycopg2.connect(conn_string)
    # conn.cursor will return a cursor object, you can use this cursor to perform queries
    cursor = conn.cursor()
    # execute our Query
    try:
        cursor.execute(sql_query)
        # retrieve the records from the database
        records = cursor.fetchall()
        t = []
        for record in records:
            table_i = re.search('[Bitmap Heap|Index|Seq] Scan.* on ([^ ]+)', record[0])
            table_i = table_i.group(1) if table_i else None
            if table_i and 'Bitmap Index Scan' not in record[0]:
                t.append(sql_db + '.' + table_i)
        t = list(set(t))  # get rid of duplicate entries in the list and sorting
        return ','.join(sorted(t))
    except psycopg2.OperationalError as err:
        sys.stderr.write(
            f"ERROR: wrong query detected in database: {sql_query}"\
            f"\nquery:\n{sql_query}\nerror:\n{err}\n"
        )
        return ''


if __name__ == '__main__':
    SPHINXCONFIG = "/etc/sphinxsearch/sphinx.conf"
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

    7) list all indexes which are based on a comma separated list of databse prefixes
    python pg2sphinx_trigger.py -c list -d stopo_dev.vd.os_realestate,stopo_dev.vd.os_dpr_mine
   \n"""

    parser = argparse.ArgumentParser(epilog=epilog, formatter_class=argparse.RawTextHelpFormatter)
    required = parser.add_argument_group('required arguments')
    optional = parser.add_argument_group('optional arguments')
    optional.add_argument(
        "-d",
        "--database_filter",
        dest="database_filter",
        default=None,
        action="store",
        help="Database Filter: optional comma separated list of database prefix"
    )
    optional.add_argument(
        "-i",
        "--index_filter",
        dest="index_filter",
        default=None,
        action="store",
        help="Index Filter: optional comma separated list of index prefix"
    )
    required.add_argument(
        "-c",
        "--command",
        dest="command",
        default="list",
        action="store",
        help="-c list: will list all the indexes touched by the database filter\n\
            -c update: will update all the indexes touched by the database filter."
    )
    required.add_argument(
        "-s",
        "--sphinxconf",
        dest="config",
        default=SPHINXCONFIG,
        action="store",
        required=True,
        help="-s /path/to/sphinx/sphinx.conf",
    )
    args = parser.parse_args()

    # Some initial tests
    if not os.path.isfile(args.config):
        sys.exit(f"ERROR: Sphinx config file doesn't exist: {args.config}")

    # -c --command
    if args.command not in ['list', 'update']:
        parser.print_help()
        sys.exit(1)

    # choose -d or -i
    if args.database_filter and args.index_filter:
        parser.print_help()
        sys.exit(1)

    filter_option = ""
    if args.database_filter:
        filter_option = 'database'

    if args.index_filter:
        filter_option = 'index'

    if args.config:
        SPHINXCONFIG = args.config

    # SQLITE Initialize and create tables in memory
    sqlite_conn = sqlite3.connect(":memory:")
    c = sqlite_conn.cursor()
    c.execute(
        """
                create table sources (
                    id INTEGER PRIMARY KEY
                    , source text
                    , source_parent text
                    , sql_db text
                    , sql_query text
                    , indexes
                    text
                    );
                    """
    )

    c.execute(
        """
                create table indexes (
                    id INTEGER PRIMARY KEY
                    , sphinx_index text
                    , index_parent
                    , source text
                    );
                    """
    )
    # switch to sqlite3 dictionary mode
    c.row_factory = sqlite3.Row

    # Read Sphinx Config
    with open(SPHINXCONFIG, "r", encoding="utf-8") as myfile:
        data = myfile.read()

    # Parse PG Connection from Sphinx Config
    CONN_HOST = re.findall(r'sql_host\s*=\s*(.*)', data)[0]
    CONN_USER = re.findall(r'sql_user\s*=\s*(.*)', data)[0]
    CONN_PWD = re.findall(r'sql_pass\s*=\s*(.*)', data)[0]
    CONN_PORT = re.findall(r'sql_port\s*=\s*(.*)', data)[0]

    # parse sphinx config sources and write them to sqlite sources table ...
    # TODO: # pylint: disable=fixme
    # regex which can extract source, sql_db and sql_query in one step
    # step 1 extract source and content in curly braces
    reg_source = re.compile(
        r'''
            ^
            source\s+                           # source start
            (?P<source>[^\n]+)                  # catch source group
            .*?                                 # Next part:
            (?P<content> (?<={)[^}]*(?=}))      # catch everything but curly braces
        ''',
        re.MULTILINE | re.DOTALL | re.VERBOSE | re.UNICODE
    )

    # Parent : Child1  -> ('Parent', 'Child1')
    # Parent2: Child2  -> ('Parent2', 'Child2')
    # Parent           -> ('Parent', None)
    parsing_func = lambda x: [p.strip() for p in x.split(':')] if ':' in x else (x.strip(), None)
    for i in reg_source.finditer(data):
        source, source_parent = parsing_func(i.groupdict()['source'])
        # step 2 extract sql_db and sql_query from curly braced content
        sql_db_name = re.search(r'sql_db\s*=\s*([\w]+)', i.groupdict()['content'])
        sql_db_name = sql_db_name.group(1) if sql_db_name else None

        sql_db_query = re.findall(
            r'^\s+sql_query\s*=(.*)$',
            i.groupdict()['content'],
            re.MULTILINE | re.DOTALL | re.VERBOSE | re.UNICODE
        )
        sql_db_query = sql_db_query[0].replace('\\',
                                               '').replace('\n',
                                                           '').strip() if sql_db_query else None
        c.execute(
            """
                    INSERT INTO sources (
                        source
                        , source_parent
                        , sql_db
                        , sql_query
                        )
                        VALUES  (? ,?, ?, ?);""",
            (source.strip(), str(source_parent).strip(), sql_db_name, sql_db_query)
        )

    # parse sphinx config indexes and write them to sqlite indexes table ...
    # TODO: # pylint: disable=fixme
    # regex which can extract source, sql_db and sql_query in one step
    # step 1 extract source and content in curly braces
    reg_index = re.compile(
        r'''
            ^
            index\s+                            # index start
            (?P<index>[^\n]+)                   # catch indexgroup
            .*?                                 # Next part:
            (?P<content> (?<={)[^}]*(?=}))      # catch everything but curly braces
        ''',
        re.MULTILINE | re.DOTALL | re.VERBOSE | re.UNICODE
    )

    # get distributed indices first
    distributed_index = {}
    for i in reg_index.finditer(data):
        index, index_parent = parsing_func(i.groupdict()['index'])
        # distributed indexes
        index_type = re.search(r'type\s=\s*(.*)', i.groupdict()['content'])
        index_type = index_type.group(1).strip() if index_type else None
        index_local = re.findall(r'local\s=\s*(.*)', i.groupdict()['content'])
        index_local = index_local if index_local else None
        if index_local:
            distributed_index[index] = index_local

    for i in reg_index.finditer(data):
        index, index_parent = parsing_func(i.groupdict()['index'])
        # step 2 extract sql_db and sql_query from curly braced content
        source = re.search(r'source\s=\s*(.*)', i.groupdict()['content'])
        source = source.group(1).strip() if source else None
        # set index_parent to distributed_index if one exists otherwise index_parent is None
        index_parent = None
        for k, v in distributed_index.items():
            if index in v:
                index_parent = k
        # import only real indexes, no distributed indexes
        if not (source is None and index_parent is None):
            c.execute(
                """
                        INSERT INTO indexes (
                            sphinx_index
                            , index_parent
                            ,source
                            ) VALUES(?, ?, ?);""",
                (index.strip(), str(index_parent).strip(), source)
            )

    # output
    sql = """
        select
            a.source as source
            , coalesce(a.sql_db,b.sql_db) as database
            , a.sql_query as sql
            , i.sphinx_index
            , i.index_parent
            FROM
            indexes i left join indexes p on trim(i.index_parent)=trim(p.sphinx_index)
            left join sources a on coalesce(i.source,p.source) = a.source
            left join sources b on a.source_parent = b.source
    """

    resultat = []
    looper_list = args.index_filter.split(",") if args.index_filter else args.database_filter.split(
        ","
    ) if args.database_filter else ["all"]
    for looper in looper_list if looper_list else []:
        index_filter = looper if args.index_filter else None
        database_filter = looper if args.database_filter else None
        for row in c.execute(sql):
            db = None
            indices = row['sphinx_index']
            indices_distributed = row['index_parent']
            # database filter
            # -d pattern
            if index_filter is None:
                if (database_filter and
                    database_filter.count('.') == 0) or (database_filter is None):
                    # db only filter can be applied to sphinx config, no need to query postgres db
                    if database_filter is None or database_filter == row['database']:
                        db = row['database']
                    # if db filter is more detailed, we have to analyze the sql
                    # queries with postgres ANALZYE VERBOSE
                elif database_filter.split(".", maxsplit=1)[0] == row['database']:
                    table = pg_get_tables(row['sql'], row['database'])
                    db = row['database'] if database_filter in table else None
            # indice filter
            # -i pattern
            else:
                if (
                    index_filter in indices or index_filter == 'all' or
                    index_filter in indices_distributed
                ):
                    db = row['database']

            # output
            if args.command == 'list' and db is not None:
                resultat.append(f"{indices} -> {db}")

            if args.command == 'update' and db is not None:
                resultat.append(f"{indices}")

    resultat = sorted(list(set(resultat)))  # get rid of duplicate entries in the list and sorting
    indent = "\n      "
    if args.command == 'list':
        if resultat:
            print(
                f"{len(resultat)} indexes are using the {filter_option}"\
                "pattern: {args.database_filter or args.index_filter}"\
                f"{indent}{indent.join(resultat)}"
                )
        else:
            print(
                f"no indexes are using the {filter_option}"\
                f"pattern: {args.database_filter or args.index_filter}"
            )
    elif args.command == 'update':
        if resultat:
            sphinx_command = f"indexer --config {args.config} --verbose {' '.join(resultat)}"
            print(sphinx_command)
            # uncomment following lines for real update
            subprocess.run(sphinx_command, shell=True, check=True)
        else:
            print(
                f"no sphinx indexes are using the {filter_option} "\
                f"pattern {args.database_filter or args.index_filter}"
            )

#
# $Id$
#
