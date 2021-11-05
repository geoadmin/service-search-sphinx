#!/bin/bash
set -euo pipefail
echo "DEBUG docker-cmd.sh"

# fancy output
green='\e[0;32m'
red='\e[0;31m'
yellow='\e[1;33m'
NC='\e[0m' # No Color

SPHINXINDEX_VOLUME="/var/lib/sphinxsearch/data/index/"
SPHINXINDEX_EFS="/var/lib/sphinxsearch/data/index_efs/"
SPHINXCONFIG="/etc/sphinxsearch/sphinx.conf"

# index arrays config, filesystem and orphaned
array_config=($(grep -E "^[^#]+ path" "${SPHINXCONFIG}" | awk -F"=" '{print $2}' | sed -n -e 's|^.*/||p'))
array_file=($(find "${SPHINXINDEX_EFS}" -maxdepth 1 -name "*.spd" | sed 's|.spd$||g' | sed -n -e 's|^.*/||p' ))
array_orphaned=($(comm -13 --nocheck-order <(printf '%s\n' "${array_config[@]}" | LC_ALL=C sort) <(printf '%s\n' "${array_file[@]}" | LC_ALL=C sort)))

# remove orphaned indexes
echo -e "${green}looking for orphaned indexes in filesystem. ${NC}"
for index in "${array_orphaned[@]}"; do
    # skip .new files, we need them to sighup searchd / rotate index updates
    if [[ ! $index == *.new ]]; then
        echo -e "\t${red} deleting orphaned index ${index} from filesystem. ${NC}"
        rm -rf "${SPHINXINDEX_EFS}${index}".*
    fi
done

# create missing indexes
echo -e "${green}check all index from sphinx.conf and create them if they dont exist on filesystem. ${NC}"
for index in ${array_config[@]}; do
    if ! $(ls "${SPHINXINDEX_EFS}${index}".* &> /dev/null); then
        echo -e "\t${yellow}creating index ${index}${NC}"
        indexer "${index}" &> /dev/null
    fi
done

# remove lock files in volume
rm ${SPHINXINDEX_VOLUME}*.spl 2> /dev/null || :

# sync new and updated indexes from efs to volume, ignore ongoing index creation (*.tmp.* files)
rsync --update --delete -av --exclude "*.tmp.*" --stats ${SPHINXINDEX_EFS} ${SPHINXINDEX_VOLUME}

# starting the searchd service
# will load the sphinx indexes from EFS --sync--> Volume --> into memory
echo -e "${green}starting searchd service ...${NC}"
/usr/bin/searchd --nodetach "$@"