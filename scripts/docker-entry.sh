#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source checker.sh
# geodata has to have rw access on probe mountpoint
chown -R geodata:geodata "${MOUNT}"

# build sphinx config with current environment
cat conf/*.part > conf/sphinx.conf.in
envsubst < conf/sphinx.conf.in > conf/sphinx.conf

# copy sphinx config and wordforms from github / image content into docker volume
cp -f conf/sphinx.conf /etc/sphinxsearch/sphinx.conf
cp -f conf/wordforms_main.txt /etc/sphinxsearch/wordforms_main.txt

# always remove lock files from mounted shared storage
rm -rf /var/lib/sphinxsearch/data/index/*.spl 2> /dev/null || :

exec gosu geodata "$@"
