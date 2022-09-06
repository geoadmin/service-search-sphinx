#!/bin/bash
set -e
set -u
set -o pipefail

# mountpoint with readiness probe file
MOUNT=$(realpath "${PROBE_MOUNTPOINT:-/tmp}")
READY_FILE="${MOUNT}/checker_ready.txt"
BOOTSTRAP_FILE="${MOUNT}/bootstrapped.txt"
PRECACHING_SECONDS=900

# get file age in seconds
function fileAge
{
    local fileMod
    if fileMod=$(stat -c %Y -- "$1")
    then
        echo $(( $(date +%s) - fileMod ))
    else
        return $?
    fi
}

clean_probe_files() {
        rm -f "${READY_FILE}" || :
        rm -f "${BOOTSTRAP_FILE}" || :
}

# source this stuff until here
[ "$0" = "${BASH_SOURCE[*]}" ] || return 0

# step 1
# skip probes during the bootstrap of the container, initial rsync
[ -e "${BOOTSTRAP_FILE}" ] || exit 0

# step 2
# if searchd is running, container is ready for connections and ready probe will be activated
if searchd --status 1> /dev/null; then
    echo "READY" > "${READY_FILE}"
    # change age of bootstrap file, readiness probe is activated now
    touch -d "${PRECACHING_SECONDS} seconds ago" "${BOOTSTRAP_FILE}"
    exit 0
fi

# step 3
# do not raise an error during the first PRECACHING_SECONDS after bootstrap (pre-cache phase)
(( $(fileAge "${BOOTSTRAP_FILE}") < PRECACHING_SECONDS )) && exit 0

# final step
# after PRECACHING_SECONDS:
# fail if searchd is not running
echo "searchd not running"
exit 1