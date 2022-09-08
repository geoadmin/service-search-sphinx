service-sphinxsearch
====================

Sphinx Search service for RE3
---------------------------------------------------

### SPHINX doc (2.2.11):

- http://sphinxsearch.com/docs/
- http://sphinxsearch.com/docs/current.html
- http://sphinxsearch.com/docs/archives/2.1.5/

### SPHINX Service Adresses:

Staging          | URL
-----------------|------------------------------------------|
**Dev:**         | http://service-sphinxsearch.dev.bgdi.ch  |
**Int:**         | http://service-sphinxsearch.int.bgdi.ch  |
**Prod:**        | http://service-sphinxsearch.prod.bgdi.ch |
**Prod public:** | http://search.geo.admin.ch               |

### Service Setup (update cycle)

```bash
$ make template
$ make move-template
$ sudo -u root systemctl stop sphinxsearch
$ sudo -u root systemctl start sphinxsearch
```

### Service Details:

**Port:**           9312

### Service paths:

Object            | Path
------------------|-----------------------------------|
**PID:**          | /var/run/sphinxsearch.pid         |
**Searchd Log**   | /var/log/sphinxsearch/searchd.log |
**Query Log:**    | /var/log/sphinxsearch/query.log   |
**Indexes:**      | /var/lib/manticore/data/index/ |
**Configuration:**| /etc/sphinxsearch/sphinx.conf     |

### Search Daemon:

#### stop

```bash
$ sudo -u root systemctl stop sphinxsearch
```

#### start

```bash
$ sudo -u root systemctl start sphinxsearch
```

#### validate config

```
$ indextool --checkconfig -c /etc/sphinxsearch/sphinx.conf
```

### Rebuild / update Indexes:
#### rebuild / build some indexes index1 index2 index3
There will be a service restart after every index

```bash
$ sudo -u sphinxsearch indexer --verbose --rotate --sighup-each --config /etc/sphinxsearch/sphinx.conf index1 index2 index3
```

#### rebuild / build all indexes

```bash
$ sudo -u sphinxsearch indexer --verbose --rotate --sighup-each --config /etc/sphinxsearch/sphinx.conf --all
```
multithread indexer is not possible: http://sphinxsearch.com/forum/view.html?id=3936a

#### Alternative

You can use the makefile in any directory containing this repository

To see options of make

```
$ make
```

#### Wordforms

Wordforms are part of the sphinx conf.
The swisssearch index (zipcodes) has to be computed after a wordforms update.

### Command line debugging with python sphinx api

```bash
$ cd test
$ python test.py -h localhost -p 9312 -i swisssearch "birgmattenweg 5"
```

### Make Deploy

Before the deploy make sure that the following steps have been done
* ```make template```
* ```make move-template```

#### Deploy config to Integration, no indexes will be built

```bash
$ make deploy-int-config
```

#### Deploy config to Integration, build all the indexes which are using the database lubis

```bash
$ make deploy-int-config db=lubis
```

#### Deploy config to Integration, build all the indexes with the given prefix

```bash
$ make deploy-int-config index=ch_tamedia_schweizerfamilie-feuerstellen
```

#### Deploy config to Integration, build all the indexes from config

You can use one of the following commands to recreate all the indexes on the deploy target from the config file. This may take a while.

```bash
$ make deploy-int-config index=all
```

```bash
$ make deploy-int-config db=all
```

The same commands can be used with ```make deploy-prod-config```.

#### Deploy config and wordforms to Integration, build all the indexes which are using wordforms

You can use the following commands to deploy the config and the wordform files and recreate all the indexes which are using wordforms. You can find the indexes with wordforms in the config files. Actually the distributed index ``swisssearch``and the indexes ``layers_**`` are using wordforms.

```bash
$ make deploy-int-config index=swisssearch
```

```bash
$ make deploy-int-config index=layers
```

The same commands can be used with ```make deploy-prod-config```.

#### Deploy config to Integration, create all indexes related to specific database

```bash
$ cd service-sphinxsearch/
$ git checkout master
$ git pull origin master
$ make template
$ make move-template
$ make deploy-int-config db=zeitreihen
```

#### Deploy **clean_index** to Integration

You can use this command to synchronize the remote sphinx config with the remote indices:
* create all the missing indexes
* remove orphaned indexes
The sphinx configuration will not be deployed. The command can be used with integration or production:
* ``$ make deploy-int-clean_index``
* ``$ make deploy-prod-clean_index``
