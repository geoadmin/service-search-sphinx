#!/bin/bash
set -e
set -u
readonly port=$1
docker run \
        --name ltclm-sphinx_$port \
        -it --rm \
        -p $port:9312 \
        -v "/var/local/efs-dev/geodata/service-sphinxsearch/dev/index/:/var/lib/sphinxsearch/data/index/" \
        ltclm-sphinx