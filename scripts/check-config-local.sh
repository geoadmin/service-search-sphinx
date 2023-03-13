#!/bin/bash
# check with indextool
set -e
set -u

# ignore hook when rebase or merge
echo "checking sphinx config and queries, be patient ..."
ERROR=$(
    for database in $(${DOCKER_EXEC_LOCAL} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c list | awk '$2 ~ /->/ {print $3}' | sort | uniq); do
        database="${database%%[[:cntrl:]]}"
        ${DOCKER_EXEC_LOCAL} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c list -d "${database}." | grep -i ERROR -a4 || continue
    done
)
[ -z "${ERROR}" ] || { echo -e "$(tput setaf 1)Nothing has been commited because of the following error in the query:\n${ERROR} $(tput sgr0)"; exit 1; }
echo "successfully finished"
