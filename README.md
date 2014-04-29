service-sphinxsearch
====================

Sphinx Search service for RE3
---------------------------------------------------

###SPHINX doc (2.1.5):
- http://sphinxsearch.com/docs/2.1.5/
- http://sphinxsearch.com/docs/manual-2.1.5.html

###SPHINX Service Adresses:
Staging    | URL
-----------|------|
**Dev:**   | http://service-sphinxsearch.dev.bgdi.ch  | 
**Int:**   | http://service-sphinxsearch.int.bgdi.ch  | 
**Prod:**  | http://service-sphinxsearch.prod.bgdi.ch  | 
**Prod public:** |  http://search.geo.admin.ch |

###Service Setup (update cycle)
```bash
$ make template
$ sudo su sphinxsearch
$ make move-template
$ /etc/init.d/sphinxsearch stop
$ /etc/init.d/sphinxsearch start
```

###Service Details:
**Port:**           9312

###Service paths:
Object    | Path
-----------|------|
**PID:**    | /var/run/sphinxsearch  | 
**Log:**|/var/www/vhosts/service-sphinxsearch/logs/sphinxsearch/|
**Indexes:**|/var/lib/sphinxsearch/data/index/|
**Configuration:**|/etc/sphinxsearch/sphinx.conf|

###Search Daemon:
```bash
$ sudo su - sphinxsearch
```

####stop
```bash
$ /etc/init.d/sphinxsearch stop
```
####start
```bash
$ /etc/init.d/sphinxsearch start
```

####validate config
```
$ indextool --checkconfig -c /etc/sphinxsearch/sphinx.conf
```
###Rebuild / update Indexes:
####rebuild / build some indexes index1 index2 index3
There will be a service restart after every index
```bash
$ indexer --verbose --rotate --sighup-each --config /etc/sphinxsearch/sphinx.conf index1 index2 index3 
```
####rebuild / build all indexes
```bash
$ indexer --verbose --rotate --sighup-each --config /etc/sphinxsearch/sphinx.conf --all
```
multithread indexer is not possible: http://sphinxsearch.com/forum/view.html?id=3936a

####Alternative
You can use the makefile in any directory containing this repository

To see options of make
```
$ make
```

To create all indices
```
make template
sudo su sphinxsearch
make move-template
make index-all
```
###Command line debugging with python sphinx api
```bash
$ cd lib/sphinxapi
$ python test.py -h localhost -p 9312 -i swisssearch "birgmattenweg 5"
```

###Make Deploy
Before the deploy make sure that the following steps have been done
* ```make template```
* ```make move-template``` with user sphinxsearch

####Deploy config to Integration, no indexes will be built
```bash
$ make deploy-conf-ab
```

####Deploy config to Integration, build all the indexes which are using the database lubis
```bash
$ make deploy-conf-ab db=lubis
```

####Deploy config to Integration, build all the indexes with the given prefix
```bash
$ make deploy-conf-ab index=ch_tamedia_schweizerfamilie-feuerstellen
```
####Deploy config to Integration, build all the indexes from config
You can use one of the following commands to recreate all the indexes on the deploy target from the config file. This may take a while.
```bash
$ make deploy-conf-ab index=all
```
```bash
$ make deploy-conf-ab db=all
```

The same commands can be used with ```make deploy-conf-prod```.
