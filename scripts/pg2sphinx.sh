#!/bin/bash
set -euo pipefail

docker_is_logged_in() {
    # this will check if the ecr token is still valid
    # the token expires after 12 hours so the credential info in
    # ~/.docker/config.json might be misleading
    docker pull "${DOCKER_IMG_LOCAL_TAG}" &> /dev/null
}

throw_error() {
    error=$1
    echo "index generation failed"
    echo "the docker command was: ${DOCKER_EXEC}"
    free -m
    docker stats --no-stream
    echo "original error code: ${error}"
    exit "${error}"
}

# check if we have read-write access to the efs
if ! /bin/test -d "${SPHINX_EFS}" -a -w "${SPHINX_EFS}"; then
    >&2 echo "no read-write access to folder ${SPHINX_EFS} available"
    exit 1
fi

# check if we are already logged in
if ! docker_is_logged_in; then
    make dockerlogin
fi

if [ -n "${DB:-}" ]; then
    # call pg2sphinx trigger with DATABASE pattern
    ${DOCKER_EXEC} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c update -d "${DB}" || { throw_error $?; }
fi

if [ -n "${INDEX:-}" ]; then
    # call pg2sphinx trigger with INDEX pattern
    ${DOCKER_EXEC} python3 pg2sphinx_trigger.py -s /etc/sphinxsearch/sphinx.conf -c update -i "${INDEX}" || { throw_error $?; }
fi

# Read config file to identify valid indexes
# Safety: If this fails, we must NOT proceed with orphan deletion to avoid removing all indexes
if ! mapfile -t array_config < <(${DOCKER_EXEC} cat /etc/sphinxsearch/sphinx.conf | grep -E "^[^#]+ path"  | awk -F"=" '{print $2}' | sed -n 's|^.*/||p' | sed 's/\r$//'); then
    >&2 echo "ERROR: Failed to read sphinx config file. Skipping orphan cleanup to avoid data loss."
    exit 0
fi

# Safety check: Ensure we actually got some indexes from the config
if [[ ${#array_config[@]} -eq 0 ]]; then
    >&2 echo "ERROR: No indexes found in sphinx config. Skipping orphan cleanup to avoid data loss."
    exit 0
fi

mapfile -t array_file < <(find "${SPHINX_EFS}" -maxdepth 1 -name "*.spd" 2> /dev/null | sed 's|.spd$||g' | sed -n -e 's|^.*/||p' )
mapfile -t array_orphaned < <(comm -13 --nocheck-order <(printf '%s\n' "${array_config[@]}" | LC_ALL=C sort) <(printf '%s\n' "${array_file[@]}" | LC_ALL=C sort))

echo "looking for orphaned indexes in filesystem."
echo "Config defines ${#array_config[@]} indexes, filesystem has ${#array_file[@]} indexes, ${#array_orphaned[@]} orphaned."

# remove orphaned indexes from EFS
for index in "${array_orphaned[@]}"; do
    # skip empty elements
    [[ -z ${index} ]] && continue
    # skip .new files, we need them to sighup searchd / rotate index updates
    if [[ ! $index == *.new ]]; then
        echo "deleting orphaned index ${index} from filesystem."
        rm -rf "${SPHINX_EFS}${index}".* || :
    fi
done

echo "finished"
