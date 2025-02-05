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
MAX_AGE=300 # max age in seconds should be the same interval as the cron settings

# check if index sync status file exists
if [[ ! -f "${LAST_SYNC}" ]]; then
    echo "index sync status file does not exist ${LAST_SYNC}"
    # reload cron / restart in case it has not been activated correctly during initial container start
    envsubst < docker-crontab | crontab
    exit 1
fi

# Calculate the time  MAX_AGE seconds ago in seconds
five_mins_ago=$(( $(date +%s) - MAX_AGE ))
# Get the file's last modification time in seconds
file_mtime=$(stat -c %Y "${LAST_SYNC}")

# check if index sync status file is up-to-date
if [[ $file_mtime -lt $five_mins_ago ]]; then
    echo "index sync status file is outdated: ${LAST_SYNC}"
    exit 1
fi
