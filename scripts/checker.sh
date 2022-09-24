#!/bin/bash
set -e
set -u
set -o pipefail

if searchd --status 1> /dev/null; then
    exit 0
else
    exit 1
fi