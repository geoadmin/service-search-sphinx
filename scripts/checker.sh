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

# source this stuff until here
[ "$0" = "${BASH_SOURCE[*]}" ] || return 0

if searchd --status 1> /dev/null; then
    echo "READY" > "${READY_FILE}"
    exit 0
else
    exit 1
fi