#!/bin/bash
set -e
echo "DEBUG docker-entry.sh"
# symlink from efs config to default container location
ln -s /var/lib/sphinxsearch/data/index/sphinx.conf /etc/sphinxsearch/sphinx.conf

# always remove lock files from mounted shared storage
rm -rf /var/lib/sphinxsearch/data/index/*.spl 2> /dev/null || :

exec "$@"