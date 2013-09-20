#!/bin/bash
SPHINXCONFIG=/etc/sphinxsearch/sphinx.conf
SPHINXINDEX=/var/lib/sphinxsearch/data/index/
if [ -z "$1" ]
then
	echo "ERROR: no deploy target specified"
	echo "usage: bash deploy_wrapper.sh <<deploy_target>>"
	echo "$ bash deploy_wrapper.sh prod"
	exit 0
else
	if [ ! -f $SPHINXCONFIG ]
	then
		echo "no sphinx configuration found in $SPHINXCONFIG -> no deploy"
	else
		echo "copying $SPHINXCONFIG to $SPHINXINDEX..."
		sudo su - sphinxsearch <<HERE
		cp $SPHINXCONFIG $SPHINXINDEX
HERE
		sudo -u deploy deploy  -r deploy.cfg $1	
	fi
fi
