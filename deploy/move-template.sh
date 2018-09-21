#!/bin/bash
# exit script on first error with status 1
set -e
# check if sudo -u sphinxsearch is working
sudo -u sphinxsearch whoami  &> /dev/null || { echo "error: script has to be run with sphinxsearch" ; exit 1 ;}

# do some stuff with sphinxsearch user

# check for sphinx.conf syntax
indextool --checkconfig -c conf/sphinx.conf | grep "config valid"
# check all database queries
for db in $(grep sql_db conf/sphinx.conf | awk 'length($3) {print $3"."}' | sort | uniq); do python deploy/pg2sphinx_trigger.py -d ${db} -c list -s conf/sphinx.conf | grep -E "^[0-9]+"; done

sudo -u sphinxsearch -s <<"EOF"
cp conf/sphinx.conf /var/lib/sphinxsearch/data/index/sphinx.conf
cp conf/wordforms_*.txt /var/lib/sphinxsearch/data/index
cp deploy/pg2sphinx_trigger.py /var/lib/sphinxsearch/data/index/pg2sphinx_trigger.py
EOF

CLEAN_INDEX=true bash deploy/hooks_conf_only/post-restore-code clean_index

# /etc/sphinxsearch is not managed by sphinxsearch user anymore but by geodata group
cp conf/sphinx.conf /etc/sphinxsearch/sphinx.conf
cp deploy/pg2sphinx_trigger.py /etc/sphinxsearch/pg2sphinx_trigger.py
exit 0
