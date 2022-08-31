#!/bin/bash
set -e
set -u
set -o pipefail


check_exit_code() {
    exit_code=$?
    # full path to output file
    local checker_file="/var/lib/container_probes/checker_ready.txt"

    # analyze exit code with trapped function
    if [ ${exit_code} -ne 0 ]; then
        # Clear the readiness file
        echo "ERROR: Liveness probe failed with code ${exit_code}" | tee "${checker_file}"
    else
        # TODO: implement robust readiness check
        #./checker_ready.sh
        echo "READY" | tee ${checker_file}
    fi
    exit ${exit_code}
}

# Capture Exit Code with trapped pseudo signal EXIT
# When the script is completed or exits for any reason, the
# commands in the check_exit_code function will be executed.
trap check_exit_code EXIT

# Do the lifeness check
searchd --status 1> /dev/null