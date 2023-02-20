#!/bin/bash
set -euo pipefail

docker_is_logged_in() {
    # this will check if the ecr token is still valid
    # the token expires after 12 hours so the credential info in
    # ~/.docker/config.json might be misleading
    docker pull "${DOCKER_IMG_LOCAL_TAG}" &> /dev/null
}

# check if we have read-write access to the efs
if ! /bin/test -d "${SPHINX_EFS}" -a -w "${SPHINX_EFS}"; then
    >&2 echo "no read-write access to folder ${SPHINX_EFS} available"
    exit 1
fi

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
