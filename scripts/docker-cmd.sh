#!/bin/bash
set -euo pipefail

# fancy output
green='\e[0;32m'
red='\e[0;31m'
yellow='\e[1;33m'
NC='\e[0m' # No Color

SPHINXINDEX="/var/lib/sphinxsearch/data/index/"
SPHINXCONFIG="/etc/sphinxsearch/sphinx.conf"

# index arrays config, filesystem and orphaned
array_config=($(grep -E "^[^#]+ path" "${SPHINXCONFIG}" | awk -F"=" '{print $2}' | sed -n -e 's|^.*/||p'))
array_file=($(find "${SPHINXINDEX}" -maxdepth 1 -name "*.spd" | sed 's|.spd$||g' | sed -n -e 's|^.*/||p' ))
array_orphaned=($(comm -13 --nocheck-order <(printf '%s\n' "${array_config[@]}" | LC_ALL=C sort) <(printf '%s\n' "${array_file[@]}" | LC_ALL=C sort)))

# remove orphaned indexes
echo -e "${green}looking for orphaned indexes in filesystem. ${NC}"
for index in "${array_orphaned[@]}"; do
    echo -e "\t${red} deleting orphaned index ${index} from filesystem. ${NC}"
    rm -rf "${SPHINXINDEX}${index}".*
done

# create missing indexes
echo -e "${green}check all index from sphinx.conf and create them if they dont exist on filesystem. ${NC}"
for index in ${array_config[@]}; do
    if ! $(ls "${SPHINXINDEX}${index}".* &> /dev/null); then
        echo -e "\t${yellow}creating index ${index}${NC}"
        indexer "${index}" &> /dev/null
    fi
done

# starting the service will load the sphinx indexes from EFS into memory
echo -e "${green}starting searchd service ...${NC}"
/usr/bin/searchd --nodetach "$@"