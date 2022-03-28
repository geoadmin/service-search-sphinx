#!/bin/bash
set -euo pipefail

if [ -n "${DB:-}" ]; then
    # call pg2sphinx trigger with DATABASE pattern
    ${DOCKER_EXEC} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c update -d "${DB}"
fi

if [ -n "${INDEX:-}" ]; then
    # call pg2sphinx trigger with INDEX pattern
    ${DOCKER_EXEC} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c update -i "${INDEX}"
fi

echo "finished"
