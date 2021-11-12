#!/bin/bash
set -euo pipefail

# symlink from efs config or volume config to default container location
if [[ -f /var/lib/sphinxsearch/data/index/sphinx.conf ]]; then
    ln -fs /var/lib/sphinxsearch/data/index/sphinx.conf /etc/sphinxsearch/sphinx.conf
elif [[ -f /var/lib/sphinxsearch/data/index_efs/sphinx.conf ]]; then
    ln -fs /var/lib/sphinxsearch/data/index_efs/sphinx.conf /etc/sphinxsearch/sphinx.conf
else
    >&2 echo "no valid sphinx config found in mounted volume or efs"
    exit 1
fi

# always remove lock files from mounted shared storage
rm -rf /var/lib/sphinxsearch/data/index/*.spl 2> /dev/null || :

exec "$@"