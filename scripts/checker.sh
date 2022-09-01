#!/bin/bash
set -e
set -u
set -o pipefail

# Do the lifeness check exit status 0 -> success | 1 -> fail
searchd --status 1> /dev/null && exit 0 || exit 1