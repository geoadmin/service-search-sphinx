service-sphinxsearch
====================

Sphinx Search service for RE3
---------------------------------------------------

###SPHINX doc (2.0.4):
```bash
http://sphinxsearch.com/docs/archives/2.0.4/
http://sphinxsearch.com/docs/archives/manual-2.0.4.html
```

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
$ searchd --stop
$ searchd
```

###Service Details:
**Port:**           9312

###Service paths:
Object    | Path
-----------|------|
**PID:**    | /var/run/sphinxsearch  | 
**Log:**|/var/www/vhosts/service-sphinxsearch/logs/sphinxsearch/|
**Indexes:**|/var/lib/sphinxsearch/data/index/|
**Configuration:**|/var/www/vhosts/service-sphinxsearch/private/service-sphinxsearch/conf/sphinx.conf|

###Search Daemon:
```bash
$ sudo su - sphinxsearch
```

####stop
```bash
$ searchd --stop
```
####start
```bash
$ searchd --config /var/www/vhosts/service-sphinxsearch/private/service-sphinxsearch/conf/sphinx.conf
```
###Rebuild / update Indexes:
####rebuild / build some indexes index1 index2 index3
There will be a service restart after every index
```bash
$ indexer --verbose --rotate --sighup-each --config /var/www/vhosts/service-sphinxsearch/private/service-sphinxsearch/conf/sphinx.conf index1 index2 index3 
```
####rebuild / build all indexes
```bash
$ indexer --verbose --rotate --sighup-each --config /var/www/vhosts/service-sphinxsearch/private/service-sphinxsearch/conf/sphinx.conf --all
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
make index-all
```
###Command line debugging with python sphinx api
```bash
$ cd lib/sphinxapi
$ python test.py -h localhost -p 9312 -i swisssearch "birgmattenweg 5"
```
