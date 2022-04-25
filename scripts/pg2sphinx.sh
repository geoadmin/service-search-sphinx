#!/bin/bash
set -euo pipefail

docker_is_logged_in() {
    jq -e --arg url "${DOCKER_REGISTRY}" '.auths | has($url)' ~/.docker/config.json > /dev/null
}

# check if we are already logged in
if ! docker_is_logged_in; then
    make dockerlogin
fi

if [ -n "${DB:-}" ]; then
    # call pg2sphinx trigger with DATABASE pattern
    ${DOCKER_EXEC} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c update -d "${DB}"
fi

if [ -n "${INDEX:-}" ]; then
    # call pg2sphinx trigger with INDEX pattern
    ${DOCKER_EXEC} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c update -i "${INDEX}"
fi

echo "finished"
