#!/bin/bash
# executed as cronjob every 15 minutes
# shellcheck disable=SC2068
set -eu
SPHINX_EFS="/var/lib/sphinxsearch/data/index_efs/"
SPHINX_VOLUME="/var/lib/sphinxsearch/data/index/"
LOG_PREFIX="[ $$ - $(date +"%F %T")] "

# every 15 minutes
    # lock only one script instance should be running
    # create list of *.new.* files in EFS
    # sync EFS->Volume
    # rotate indexes
    # sync back rotated Indexes to EFS
    # remove *.new.* files FROM EFS

LOCKFILE="/var/lock/$(basename "$0")"
LOCKFD=99

# PRIVATE
_lock()             { flock -"$1" "$LOCKFD"; }
_no_more_locking()  { _lock u; _lock xn && rm -f "$LOCKFILE"; }
_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\""; trap _no_more_locking EXIT; }

# ON START
_prepare_locking

# PUBLIC
exlock_now()        { _lock xn; }  # obtain an exclusive lock immediately or fail

# Simplest example is avoiding running multiple instances of script.
exlock_now || { echo "${LOG_PREFIX}locked"; exit 1; }
echo "${LOG_PREFIX}start"

# collect some metadata for a smart rsync
# we have to detect the following use cases:
    # index files are new, not yet roteated
    # index files are new, already rotated on another node
# this is the array of index files that are new on EFS and outdated in the local volume, they have been rotated updated already elsewhere
mapfile -t new_files_rotated < <(rsync --update -avin --delete --exclude '*.tmp.*' --exclude '*.new.*' --include '*.sp*' --exclude '*' ${SPHINX_EFS} ${SPHINX_VOLUME} | grep -E '^>.*.sp.*$' | awk '{print $2}')
# this is the array of new index files that are new on EFS and not yet rotated
mapfile -t new_files < <(rsync --update -avin --delete --exclude '*.tmp.*' ${SPHINX_EFS} ${SPHINX_VOLUME} | grep -E '^>.*.new.*' | awk '{print $2}')
# this array will merge the combination of these two arrays
mapfile -t new_files_merged < <(echo "${new_files[@]}")

# sync EFS to VOLUME
echo "${LOG_PREFIX}sync efs to volume (${SPHINX_EFS} -> ${SPHINX_VOLUME})"
rsync --update -av --delete --exclude '*.tmp.*' ${SPHINX_EFS} ${SPHINX_VOLUME}

# rename already rotated files before index rotation from *.sp* to .*.new.sp*
echo "${LOG_PREFIX}-> $(date +"%F %T") rename already rotated, new index files: ${new_files_rotated[*]}..."

# strip file extension from filename and expand it to the full list of existing files in SPHINX Volume
pushd "${SPHINX_VOLUME}"
tmp_array=()
for new_file in "${new_files_rotated[@]}";do
    # skip empty elements
    [[ -z ${new_file} ]] && continue
    base=${new_file%.*}
    tmp_array+=("${base}"*)
done
if ((${#tmp_array[@]})); then
    mapfile -t new_files_rotated < <(printf "%s\n" "${tmp_array[@]}" | sort -u | tr '\n' ' ')
    for rotated in ${new_files_rotated[@]}; do # shellcheck disable=SC2068
        # skip empty elements
        [[ -z ${rotated} ]] && continue
        base=${rotated%.*}
        extension=${rotated##*.}
        new_file="${base}.new.${extension}"
        mv -f "${rotated}" "${new_file}"
        new_files_merged+=("${new_file}")
    done
fi
popd

# remove duplicates from array
mapfile -t new_files_merged < <(printf "%s\n" "${new_files_merged[@]}" | sort -u | tr '\n' ' ')

# start index rotation
pkill -1 searchd

# wait until all files new_files and locally renamed files have been renamed / rotated in SPHINX_VOLUME
all_files_are_gone=false
while ! ${all_files_are_gone}; do
    all_files_are_gone=true
    for new_file in "${new_files_merged[@]}"; do
        # skip empty elements
        [[ -z ${new_file} ]] && continue
        [ -f "${SPHINX_VOLUME}${new_file}" ] && all_files_are_gone=false
    done
    sleep 1
done

echo "${LOG_PREFIX}-> $(date +"%F %T") sync volume to efs (${SPHINX_VOLUME} -> ${SPHINX_EFS})"
rsync --update -av --exclude '*.tmp.*' --exclude '*.new.*' --exclude '*.spl' --include '*.sp*' --exclude '*' ${SPHINX_VOLUME} ${SPHINX_EFS}

# delete new files list from rsync from EFS
echo "${LOG_PREFIX}-> $(date +"%F %T") delete new files list from sync"
for new_file in "${new_files[@]}"; do
    # skip empty elements
    [[ -z ${new_file} ]] && continue
    rm "${SPHINX_EFS}${new_file}" -rf || :
done

echo "${LOG_PREFIX}-> $(date +"%F %T") finished"