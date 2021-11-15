#!/bin/bash
set -euo pipefail

LOCK_TAG=${DOCKER_INDEX_VOLUME}_maintenance_lock

lock() {
    # check if a maintenance job is running already already
    # only one maintenance job / container is allowed to run to avoid disk sphinx config conflicts (*.new.* files, *.tmp.* files)
    # wait loop for one hour
    counter=0
    max_counter=60 # max loops
    nap_time=60 # loop time in seconds
    while docker ps -a --format '{{.Names}}' | grep --silent "${LOCK_TAG}" -w; do
        ((counter+=1))
        if (( counter > max_counter )); then
            >&2 echo "maintenance operations are locked"
            exit 1
        fi
        echo "sphinx maintenance job is already running, loop ${counter}/${max_counter} every ${nap_time} seconds ..."
        sleep ${nap_time}
    done

    docker run \
        --rm \
        -d \
        -t \
        -v "${SPHINX_INDEX}":/var/lib/sphinxsearch/data/index/ \
        --name "${LOCK_TAG}" \
        "${DOCKER_IMG_LOCAL_TAG}" /bin/bash
}

unlock() {
    docker stop "${LOCK_TAG}"
}

trap "unlock" exit
lock

if [ -n "${DB:-}" ]; then
    # call pg2sphinx trigger with DATABASE pattern
    ${DOCKER_EXEC} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c update -d "${DB}"
fi

if [ -n "${INDEX:-}" ]; then
    # call pg2sphinx trigger with INDEX pattern
    ${DOCKER_EXEC} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c update -i "${INDEX}"
fi

echo "finished"