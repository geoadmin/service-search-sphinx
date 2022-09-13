#!/bin/bash
# executed as cronjob every 15 minutes
# shellcheck disable=SC2068
set -eu
SPHINX_EFS="/var/lib/sphinxsearch/data/index_efs/"
SPHINX_VOLUME="/var/lib/sphinxsearch/data/index/"
SPHINXCONFIG="/etc/sphinxsearch/sphinx.conf"
RSYNC_INCLUDE="/tmp/include.txt"
LOG_PREFIX="[ $$ - $(date +"%F %T")] "

# every 15 minutes
    # lock only one script instance should be running
    # create list of updated files in EFS
    # sync EFS->Volume
    # rotate indexes

# only the following file extensions will be synced from efs to docker:
    # http://sphinxsearch.com/docs/current/conf-path.html
    # .spa stores document attributes (used in extern docinfo storage mode only);
    # .spd stores matching document ID lists for each word ID;
    # .spe stores skip-lists to speed up doc-list filtering
    # .sph stores index header information;
    # .spi stores word lists (word IDs and pointers to .spd file);
    # .spk stores kill-lists;                                                           # will never be updated by database trigger
    # .spm stores MVA data;                                                             # will never be updated by database trigger
    # .spp stores hit (aka posting, aka word occurrence) lists for each word ID;
    # .sps stores string attribute data.

# only indexes will be synced to docker volume that have been updated completely updated on EFS,
# a completely updated index consists of the following 7 new files:
    # .spd
    # .spe
    # .sph
    # .spi
    # .spp
    # .sps

SPHINX_FILE_EXTENSIONS=('spa' 'spd' 'spe' 'sph' 'spi' 'spk' 'spm' 'spp' 'sps')
SPHINX_INDEX_READY=('spd' 'spe' 'sph' 'spi' 'spp' 'sps')
SPHINX_INDEXES=$(grep -E "^[^#]+ path" "${SPHINXCONFIG}" | awk -F"=" '{print $2}' | sed -n -e 's|^.*/||p')

# global locking, no parallel syncing from efs into docker volumes
LOCKFILE="${SPHINX_EFS}$(basename "$0")"
LOCKFD=99

# PRIVATE
_lock()             { flock -"$1" "$LOCKFD"; }
_no_more_locking()  { _lock u; _lock xn && rm -f "$LOCKFILE"; }
_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\""; trap _no_more_locking EXIT; }

# do not continue if searchd is not running for crash or precaching reasons...
searchd --status &> /dev/null || { echo "${LOG_PREFIX}-> $(date +"%F %T") searchd service is not running, skip rsync"; exit 0; }

# ON START
_prepare_locking

# PUBLIC
exlock_now()        { _lock xn; }  # obtain an exclusive lock immediately or fail

# avoiding running multiple instances of script.
exlock_now || { echo "${LOG_PREFIX}-> $(date +"%F %T") locked"; exit 1; }
echo "${LOG_PREFIX}-> $(date +"%F %T") start"

check_if_index_is_ready() {
    # input:
    #   $1: index name
    #   ${SPHINX_INDEX_READY} array of mandatory file extensions
    #   ${new_files} file array from rsync dry-run
    # 
    # output: true|false if index is ready for sync / fully updated
    #   all the extensions from the Array SPHINX_INDEX_READY have to exist in the array
    local index_name found_extensions ready
    index_name="$1"
    ready=0
    # get index extensions from the new files array
    mapfile -t found_extensions < <(
        for new_file in "${new_files[@]}"; do
            case "$new_file" in
                "${index_name}"*) echo "${new_file##*.}" ;;
            esac
        done
    )
    # check if all the extensions from ${SPHINX_INDEX_READY} are available in the new files array
    for ready_extension in ${SPHINX_INDEX_READY[@]}; do
        if ! printf '%s\0' "${found_extensions[@]}" | grep -Fxqz -- "${ready_extension}"; then
            ready=1
        else
            # if the mandatory file extension exists
            # check if the mandatory file has a filesize > 0
            local_file="${SPHINX_EFS}${index_name}.${ready_extension}"
            test -s "${local_file}" || ready=1
        fi
    done
    return ${ready}
}

# loop through all indexes from sphinx config and sync them if the have been fully updated on efs
for sphinx_index in ${SPHINX_INDEXES[@]}; do
    # create include-from file from sphinx config for selective rsync from EFS -> LOCAL
    : > "${RSYNC_INCLUDE}"
    for extension in ${SPHINX_FILE_EXTENSIONS[@]}; do
        printf "%s.%s\\n" "${sphinx_index}" "${extension}"
    done > "${RSYNC_INCLUDE}"

    # collect some metadata for a smart rsync
    # we have to detect the following use cases:
        # index files are new on efs and not yet rotated on local docker volume
    # this is the array of all index files that are new on EFS and outdated in the local volume
    mapfile -t new_files < <(rsync --update -avin --delete --include-from "${RSYNC_INCLUDE}" --exclude '*' ${SPHINX_EFS} ${SPHINX_VOLUME} | grep -E '^>.*.sp.*$' | awk '{print $2}')

    # skip if new_files is empty no new files have been found with that pattern on EFS
    (( ${#new_files[@]} )) || continue

    # check if index has been fully updated on EFS
    check_if_index_is_ready "${sphinx_index}" || { echo "${LOG_PREFIX}-> $(date +"%F %T") skipping partially updated index: ${sphinx_index} ..."; continue; }

    # sync EFS to VOLUME
    echo "${LOG_PREFIX}-> $(date +"%F %T") start sync and rename files in target folder: ${sphinx_index} ..."
    tmp_array=()

    while IFS= read -r -d '' new_file; do
        new_file=$(basename "${new_file}")
        # shellcheck disable=2001
        new_file_renamed=$(sed 's/\.sp\(\w\)$/.new.sp\1/' <<< "${new_file}")
        cp -fa "${SPHINX_EFS}${new_file}" "${SPHINX_VOLUME}${new_file_renamed}"
        tmp_array+=("${new_file_renamed}")
    done <   <(find "${SPHINX_EFS}" -name "${sphinx_index}*" -print0)

    if ((${#tmp_array[@]})); then
        # remove blank strings from array
        IFS=" " read -r -a new_files_merged <<< ${tmp_array[@]}
        if ((${#new_files_merged[@]})); then
            # start index rotation
            echo "${LOG_PREFIX}-> $(date +"%F %T") restart searchd for index rotation..."
            pkill -1 searchd

            # wait until all files new_files and locally renamed files have been renamed / rotated in SPHINX_VOLUME
            echo "${LOG_PREFIX}-> $(date +"%F %T") wait for index rotation..."
            all_files_are_gone=false
            while ! ${all_files_are_gone}; do
                all_files_are_gone=true
                for new_file in ${new_files_merged[@]}; do
                    # skip empty elements
                    [[ -z ${new_file} ]] && continue
                    [ -f "${SPHINX_VOLUME}${new_file}" ] && all_files_are_gone=false
                done
                sleep 5
            done
        fi
    fi
done


echo "${LOG_PREFIX}-> $(date +"%F %T") finished"