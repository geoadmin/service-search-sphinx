#!/bin/bash
set -e
set -u
set -o pipefail

# readiness probe file
READY_FILE="/var/lib/container_probes/checker_ready.txt"

clean_probe_files() {
    rm -f "${READY_FILE}" || :
}

# source this stuff until here
[ "$0" = "${BASH_SOURCE[*]}" ] || return 0

if searchd --status 1> /dev/null; then
    echo "READY" > "${READY_FILE}"
    exit 0
else
    clean_probe_files
    exit 1
fi