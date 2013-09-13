service-sphinxsearch
====================

Sphinx Search service for RE3
---------------------------------------------------

###SPHINX Service Adresses:
Staging    | URL
-----------|------|
**Dev:**   | http://service-sphinxsearch.dev.bgdi.ch  | 
**Int:**   | http://service-sphinxsearch.int.bgdi.ch  | 
**Prod:**  | http://service-sphinxsearch.prod.bgdi.ch  | 
**Prod public:** |  http://search.geo.admin.ch |

###Service Details:
**Port:**           9312

###Service paths:
Object    | Path
-----------|------|
**PID:**    | /var/run/sphinxsearch  | 
**Log:**|/var/log/sphinxsearch/|
**Indexes:**|/var/lib/sphinxsearch/data/|
**Configuration:**|/etc/sphinxsearch/sphinx.conf|

###Search Daemon:
`$ sudo su - sphinxsearch`
####stop
`$ searchd --stop`
####start
`$ searchd --start`
###Rebuild / update Indexes:
####rebuild / build some indexes index1 index2 index3
There will be a service restart after every index

`$indexer --verbose --rotate --sighup-each index1 index2 index3 `

####rebuild / build all indexes

`$indexer --verbose --rotate --sighup-each --all`

multithread indexer is not possible: http://sphinxsearch.com/forum/view.html?id=3936

###Command line debugging with python sphinx api
`$ cd lib/sphinxapi`

`$ python test.py -h localhost -p 9312 -i swisssearch "birgmattenweg 5"`
