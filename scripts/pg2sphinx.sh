#!/bin/bash
set -euo pipefail

# check if a maintenance job is running already
# only one maintenance job / container is allowed to run to avoid disk sphinx config conflicts (*.new.* files, *.tmp.* files)
# wait loop for one hour
counter=0
max_counter=60 # max loops
nap_time=60 # loop time in seconds
while docker ps -a --format {{.Names}} | grep --silent ${DOCKER_LOCAL_TAG}_maintenance -w; do
    ((counter+=1))
    if (( ${counter} > ${max_counter} )); then
        >&2 echo "maintenance operations are locked"
        exit 1
    fi
    echo "sphinx maintenance job is already running, loop ${counter}/${max_counter} every ${nap_time} seconds ..."
    sleep ${nap_time}
done

if [ ! -z ${DB:-} ]; then
    # call pg2sphinx trigger with DATABASE pattern
    ${DOCKER_EXEC} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c update -d ${DB}
fi

if [ ! -z ${INDEX:-} ]; then
    # call pg2sphinx trigger with INDEX pattern
    ${DOCKER_EXEC} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c update -i ${INDEX}
fi

echo "update container"
# filter by volume, all the containers with the same volume are updated
for container in $(docker ps -a --format {{.Names}} --filter volume=${DOCKER_INDEX_VOLUME}); do
    echo ""
    echo "rotating indexes on container ${container}..."
    docker exec -it "${container}" /bin/bash -c "rsync --update -av --delete --exclude '*.tmp.*' /var/lib/sphinxsearch/data/index_efs/ /var/lib/sphinxsearch/data/index/ && pkill -1 searchd && searchd --status"
done

# clean EFS from *.new.* files
find ${SPHINX_INDEX} -name "*.new.*" -delete

echo "finished"