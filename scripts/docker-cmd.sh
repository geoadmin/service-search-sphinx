#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

# fancy output
green='\e[0;32m'
NC='\e[0m' # No Color

SPHINXINDEX_VOLUME="/var/lib/sphinxsearch/data/index/"
SPHINXINDEX_EFS="/var/lib/sphinxsearch/data/index_efs/"
K8S_EFS="/var/local/geodata/service-sphinxsearch/${DBSTAGING}/index/"

# TODO: This switch can be removed after the migration to k8s
# in k8s we have to use /var/local/ as mountpoint for the index files from geodata efs
# /var/local/geodata/service-sphinxsearch/${DBSTAGING}/index/
if [ -d "${K8S_EFS}" ]; then
    echo "service is running on k8s, index files have been found on ${K8S_EFS}."
    SPHINXINDEX_EFS="${K8S_EFS}"
fi

# remove lock files in volume
rm ${SPHINXINDEX_VOLUME}*.spl 2> /dev/null || :

# sync new and updated indexes from efs to volume, ignore ongoing index creation (*.tmp.* files)
rsync --update --delete -av --exclude "*.tmp.*" --stats ${SPHINXINDEX_EFS} ${SPHINXINDEX_VOLUME} || :

# start cron service as geodata user only if container is started in service mode (no cmd has been passed to docker run)
# cron will sync every n minutes EFS to Docker volume and send a SIGHUP to searchd service
service cron start || exit 1
envsubst < docker-crontab | crontab # DBSTAGING will be read from container environment

# starting the searchd service
# will load the sphinx indexes from EFS --sync--> Volume --> into memory
echo -e "${green}starting searchd service ...${NC}"

# prepare the applogs for output on /proc/1/fd/1
tail --pid $$ -F /var/log/sphinxsearch/searchd.log &
tail --pid $$ -F /var/log/sphinxsearch/query.log &

# prepare the logs for the cronjobs
# Have the main Docker process tail the files to produce stdout and stderr
# for the main process that Docker will actually show in docker logs.
tail -f /tmp/stdout &
tail -f /tmp/stderr >&2 &

# searchd will own pid 1
exec /usr/bin/searchd  --nodetach "$@"
