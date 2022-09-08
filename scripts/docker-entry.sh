#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source checker.sh

# build sphinx config with current environment
cat conf/*.part > conf/manticore.conf.in
envsubst < conf/manticore.conf.in > conf/manticore.conf

# copy sphinx config and wordforms from github / image content into docker volume
cp -f conf/manticore.conf /etc/manticoresearch/manticore.conf
cp -f conf/wordforms_main.txt /etc/manticoresearch/wordforms_main.txt

# always remove lock files from mounted shared storage
rm -rf /var/lib/manticore/data/index/*.spl 2> /dev/null || :

exec "$@"