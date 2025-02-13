#!/bin/bash
set -e
set -u
set -o pipefail

# the service is considered to be ready for connections if
    # searchd --status is running
    # last sync of index files exists and is not older than 5 minutes

# check if searchd is running
searchd --status 1> /dev/null || exit 1

# check if index files are up-to-date
LAST_SYNC="/tmp/last_sync_finished.txt"
# max age in seconds, default value should be at least the same interval as the cron settings in docker-crontab, default 5 minutes (300 seconds)
# in productive systems it is better to use a higher value, e.g. 2x300s = 600s
MAX_AGE=${MAX_AGE:-300}

# check if index sync status file exists
if [[ ! -f "${LAST_SYNC}" ]]; then
    echo "index sync status file does not exist ${LAST_SYNC}"
    # reload cron / restart in case it has not been activated correctly during initial container start
    envsubst < docker-crontab | crontab
    exit 1
fi

# check if index-sync-rotate.sh is currently running with the lock file
# if a sync is currently running, further tests should not be executed
LOCK_FILE="/tmp/index-sync-rotate.sh"
if [[ -f "${LOCK_FILE}" ]]; then
	echo "$(basename "${LOCK_FILE}") is currently running. Exiting."
    exit 0
fi

# check if index sync status file is up-to-date
if [[ $(stat -c %Y "${LAST_SYNC}") -lt $(( $(date +%s) - MAX_AGE )) ]]; then
    echo "index sync status file is outdated: ${LAST_SYNC}"
    exit 1
fi
