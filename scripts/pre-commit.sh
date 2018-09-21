#!/bin/bash
# check with indextool
BRANCH_NAME=$(git branch | grep '*' | sed 's/* //')

# ignore hook when rebase or merge
if [ $BRANCH_NAME != '(no branch)' ]; then
    echo "make template ..."
    ( make template 1> /dev/null) || { echo "$(tput setaf 1)Nothing has been commited because of an error in the sphinx configuration$(tput sgr0)"; exit 1; }

    # check queries
    echo "checking queries ..."
ERROR=$( {
for database in $(python deploy/pg2sphinx_trigger.py -s conf/sphinx.conf -c list | awk '$2 ~ /->/ {print $3}' | sort | uniq); do echo $database; python deploy/pg2sphinx_trigger.py -s conf/sphinx.conf -c list -d ${database}.; done 1> /dev/null
} 2>&1
)
    [ -z "${ERROR}" ] || { echo -e "$(tput setaf 1)Nothing has been commited because of the following error in the query:\n${ERROR} $(tput sgr0)"; exit 1; }
    echo "succesfully finished"
fi
