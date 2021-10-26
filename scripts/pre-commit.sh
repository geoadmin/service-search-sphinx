#!/bin/bash
set -e
set -u
set -o pipefail

BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
TEST=false
echo "start hook"
# ignore hook when rebase or merge
if [ "${BRANCH_NAME}" != '(no branch)' ]; then
    while read -r st file; do
        echo "checking $st $file ..."
        # skip deleted files
        if [ "$st" == 'D' ]; then continue; fi

        # do a check only if conf/*.part files have been modified / staged
        if [[ "$file" =~ (.part)$ ]]; then
            echo "detected changes in file $file"
            TEST=true
        fi
    done < <(git diff --cached --name-status)
fi

if [ "$TEST" = "true" ]; then
    make check-config-local
fi