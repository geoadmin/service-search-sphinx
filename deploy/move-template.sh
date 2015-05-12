#!/bin/bash
# exit script on first error with status 1
set -e
# check user
[ "$USER" = "sphinxsearch" ] || { echo "error: script has to be run with sphinxsearch" ; exit 1 ;}
indextool --checkconfig -c conf/sphinx.conf | grep "config valid"
cp conf/sphinx.conf /var/lib/sphinxsearch/data/index/sphinx.conf
cp conf/wordforms_*.txt /var/lib/sphinxsearch/data/index
cp conf/stopwords_*.txt /var/lib/sphinxsearch/data/index
cp conf/sphinx.conf /etc/sphinxsearch/sphinx.conf
cp deploy/pg2sphinx_trigger.py /var/lib/sphinxsearch/data/index/pg2sphinx_trigger.py
cp deploy/pg2sphinx_trigger.py /etc/sphinxsearch/pg2sphinx_trigger.py
CLEAN_INDEX=true bash deploy/hooks_conf_only/post-restore-code clean_index
exit 0
