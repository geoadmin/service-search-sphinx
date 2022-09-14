#!/bin/bash
set -e
set -u
set -o pipefail

# mountpoint with readiness probe file
MOUNT=$(realpath "${PROBE_MOUNTPOINT:-/tmp}")
READY_FILE="${MOUNT}/checker_ready.txt"

clean_probe_files() {
    rm -f "${READY_FILE}" || :
}

swisssearch_status() {
        mysql -P 9306 -h 0 -e "SELECT * FROM swisssearch where match('landstrasse 78');"
}

searchd_status() {
        searchd --status
}

# source this stuff until here
[ "$0" = "${BASH_SOURCE[*]}" ] || return 0

if searchd_status 1> /dev/null && swisssearch_status 1> /dev/null; then
    echo "READY" > "${READY_FILE}"
    exit 0
else
    clean_probe_files
    exit 1
fi