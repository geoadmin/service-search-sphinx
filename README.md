service-sphinxsearch
====================

Sphinx Search service for RE3
---------------------------------------------------

### SPHINX doc (2.2.11):

- http://sphinxsearch.com/docs/
- http://sphinxsearch.com/docs/current.html
- http://sphinxsearch.com/docs/archives/2.1.5/

### Setup
The fsdi sphinxsearch consists of the following services:
* [service-search-wsgi](https://github.com/geoadmin/service-search-wsgi) (port 80)
* [service-sphinxsearch](https://github.com/geoadmin/service-sphinxsearch) (port 9312)

The service configuration is in this [docker-compose](https://github.com/geoadmin/infra-vhost/blob/master/systems/api3/service-search/base/docker-compose.yml) file:

### service-search-wsgi adresses

Staging          | URL
-----------------|------------------------------------------|
**Dev:**         | https://sys-api3.dev.bgdi.ch/rest/services/api/SearchServer  |
**Int:**         | https://sys-api3.int.bgdi.ch/rest/services/api/SearchServer  |
**Prod:**        | https://api.geo.admin.ch/rest/services/api/SearchServer |

### service-sphinxsearch container setup

The sphinxsearch container/image can be operated in
* **maintenance mode** (index creation / update)
* **service mode** (sphinxsearch service on port 9312)

### Service paths inside the running container

Object            | Path
------------------|-----------------------------------|
**PID:**          | /var/run/sphinxsearch/searchd.pid |
**Searchd Log**   | /var/log/sphinxsearch/searchd.log |
**Query Log:**    | /var/log/sphinxsearch/query.log   |
**Indexes:**      | /var/lib/sphinxsearch/data/index/ |
**Configuration:**| /etc/sphinxsearch/sphinx.conf     |

### maintenance mode
#### local index config validation
```bash
make check-config-local
```
This check is automatically executed with Codebuild for each Pull request.

#### local index creation
```bash
STAGING=dev DB=bod_dev make pg2sphinx
```
For this command you need read-write access to `${SPHINX_EFS}`.
This command is executed/triggered by the database deploy script on `geodatasync.prod.bgdi.ch`.

### service mode
#### local sphinxsearch server
You can run a local sphinxsearch server on port 9312 with the following make targets:
```bash
make dockerrun
make dockerrundebug
```

the initial start of this local container will copy all the index files from the efs folder to a local docker volume. This initial ramp up process can take up to an hour! You will need at least **70 GB of free diskspace** on your host.

In the running service container, the indexes are synced every 15 minutes from efs to the local volume and rotated. This is done with the script index-sync-rotate.sh.

The sphinxsearch logs (searchd and query logs) and the index-sync-rotate.sh logs are redirected to stdout inside the container and are visible with `docker logs`.

### Deploy
Since the service is operated on vhosts, the deploy of the search stack (service-search-wsgi and service-sphinxsearch) is done with this [deploy script](https://github.com/geoadmin/infra-vhost/blob/master/deploy.sh).

See [here](https://github.com/geoadmin/doc-guidelines/blob/master/DEPLOY.md#1-sphinx-search---int) for more information.

### Wordform

Wordforms are part of the sphinx conf.
The swisssearch index (zipcodes) has to be computed after a wordforms update.

### Command line debugging with python sphinx api
```bash
cd test
python test.py -h localhost -p 9312 -i swisssearch "birgmattenweg 5"
```

### Command line debugging with MYSQL interface
You can access the Sphinx indexes using the MySQL client from inside the Sphinx pods.
First, open a bash terminal inside a Sphinx container.
```bash
$ kubectx bgdi/dev
$ kubectl -n service-search exec -it service-search-0 -c sphinx -- bash
$ mysql -h 127.0.0.1 -P 9306

$ MySQL [(none)]> select count(*) FROM ch_swisstopo_swissboundaries3d_gemeinde_flaeche_fill;
+----------+
| count(*) |
+----------+
|   546474 |
+----------+
1 row in set (0.009 sec)

# expanded output for better readability
MySQL [(none)]> select * FROM ch_swisstopo_swissboundaries3d_gemeinde_flaeche_fill limit 1\G
*************************** 1. row ***************************
                id: 1
            origin: feature
            detail: aeugst am albis 1
             layer: ch.swisstopo.swissboundaries3d-gemeinde-flaeche.fill
    geom_quadindex: 0300210
               lat: 47.274960
               lon: 8.490504
     geom_st_box2d: BOX(678109.8793882465 234561.19507542154,681154.069340285 238543.8333016288)
geom_st_box2d_lv95: BOX(2678110.6950000003 1234561.039999999,2681154.916000001 1238543.664999999)
             label: Aeugst am Albis 2026
              year: 2026
        feature_id: 1
1 row in set (0.008 sec)
```
