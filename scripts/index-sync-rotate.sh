#!/bin/bash
# executed as cronjob every 15 minutes
# shellcheck disable=SC2068
set -eu
SPHINX_EFS="/var/lib/sphinxsearch/data/index_efs/"
K8S_EFS="/var/local/geodata/service-sphinxsearch/${DBSTAGING}/index/"

SPHINX_VOLUME="/var/lib/sphinxsearch/data/index/"
SPHINXCONFIG="/etc/sphinxsearch/sphinx.conf"
RSYNC_INCLUDE="/tmp/include.txt"

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
# a completely updated index consists of the following new files:
    # .spd
    # .spe
    # .sph
    # .spi
    # .spp
    # .sps


json_logger() {
    log_level=$1
    timestamp=$(date --utc +%FT%T.%3NZ)
    self=$(readlink -f "${BASH_SOURCE[0]}")
    self=$(basename "$self")
    jq --raw-input --compact-output --monochrome-output \
    '{
        "time": "'"${timestamp}"'",
        "level": "'"${log_level}"'",
        "logger": "'"${self}"'",
        "pidTid": "'$$'",
        "function": "'"${FUNCNAME[0]}"'",
        "message": .
    }'
}

SPHINX_FILE_EXTENSIONS=('spa' 'spd' 'spe' 'sph' 'spi' 'spk' 'spm' 'spp' 'sps')
SPHINX_INDEX_READY=('spd' 'spe' 'sph' 'spi' 'spp' 'sps')
SPHINX_INDEXES=$(grep -E "^[^#]+ path" "${SPHINXCONFIG}" | awk -F"=" '{print $2}' | sed -n -e 's|^.*/||p')

LOCKFILE="/tmp/$(basename "$0")"
LOCKFD=99
touch /tmp/last_sync_start.txt || :

# PRIVATE
_lock()             { flock -"$1" "$LOCKFD"; }
_no_more_locking()  { _lock u; _lock xn && rm -f "$LOCKFILE"; }
_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\""; trap _no_more_locking EXIT; }

# do not continue if searchd is not running for crash or precaching reasons...
searchd --status &> /dev/null || { echo "searchd service is not running, skip rsync" | json_logger INFO; exit 0; }

# ON START
_prepare_locking

# PUBLIC
exlock_now()        { _lock xn; }  # obtain an exclusive lock immediately or fail

# avoiding running multiple instances of script.
exlock_now || { echo "locked" | json_logger INFO; exit 1; }
echo "start" | json_logger INFO

# TODO: This switch can be removed after the migration to k8s
# in k8s we have to use /var/local/ as mountpoint for the index files from geodata efs
# /var/local/geodata/service-sphinxsearch/${DBSTAGING}/index/
set_efs_source() {
    # input:
    #   ${SPHINX_EFS} mountpoint of efs index files
    # 
    # output: SPHINX_EFS
    #   if the index files are available on the k8s mountpoint, the k8s mountpoint will be used
    #   as efs index source
    if [ -d "${K8S_EFS}" ]; then
        echo "service is running on k8s, index files have been found on ${K8S_EFS}." | json_logger INFO
        SPHINX_EFS="${K8S_EFS}"
    fi
}

check_if_efs_index_is_ready() {
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

check_if_local_index_is_ready() {
    # input:
    #   $1: index name
    #   ${SPHINX_INDEX_READY} array of mandatory file extensions
    # 
    # output: true|false if index is ready for rotation
    #   all the extensions from the Array SPHINX_INDEX_READY have to exist in the array and should not be empty
    #   if one of the mandatory extensions has been updated between test check_if_efs_index_is_ready and copy, skip the rotation and remove the new files in the local volume
    #   this has to be done to avoid an eternal loop in the following clean-up
    #   p.e. WARNING: rotating index 'layers_fr': prealloc: failed to load /var/lib/sphinxsearch/data/index/layers_fr.new.spi: bad size 0 (at least 1 bytes expected); using old index
    #   the index will never be rotated and the new files are blocking the successful termination of the script

    local index_name ready
    index_name="$1"
    ready=0

    pushd "${SPHINX_VOLUME}"
    for extension in ${SPHINX_INDEX_READY[@]}; do
        mandatory_file=${index_name}.new.${extension}
        test -s "$mandatory_file" || {
            echo "mandatory file ${mandatory_file} is missing or empty..." | json_logger INFO
            ready=1
        }
    done
    if ((ready == 1)); then
        rm "${index_name}".new.* -rf &> /dev/null || :
    fi
    popd
    return ${ready}
}

set_efs_source

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
    mapfile -t new_files < <(rsync --update -avin --delete --include-from "${RSYNC_INCLUDE}" --exclude '*' "${SPHINX_EFS}" ${SPHINX_VOLUME} | grep -E '^>.*.sp.*$' | awk '{print $2}')

    # skip if new_files is empty no new files have been found with that pattern on EFS
    (( ${#new_files[@]} )) || continue

    # check if index has been fully updated on EFS
    check_if_efs_index_is_ready "${sphinx_index}" || { echo "skipping partially updated index: ${sphinx_index} ..." | json_logger INFO; continue; }

    # sync EFS to VOLUME
    echo "start sync and rename files in target folder: ${sphinx_index} ..." | json_logger INFO
    tmp_array=()
    # find and copy only files with valid file extension
    # find will be expanded to:
    # find /var/local/geodata/service-sphinxsearch/prod/index/ -regex "^.*/layers_de.\(spa\|spd\|spe\|sph\|spi\|spk\|spm\|spp\)$^
    find_extensions="${SPHINX_FILE_EXTENSIONS[*]}"
    while IFS= read -r -d '' new_file; do
        echo "copy new file: $new_file" | json_logger INFO
        new_file=$(basename "${new_file}")
        # shellcheck disable=2001
        new_file_renamed=$(sed 's/\.sp\(\w\)$/.new.sp\1/' <<< "${new_file}")
        cp -fa "${SPHINX_EFS}${new_file}" "${SPHINX_VOLUME}${new_file_renamed}"
        tmp_array+=("${new_file_renamed}")
    done <   <(find "${SPHINX_EFS}" -regex "^.*/${sphinx_index}.\(${find_extensions// /\\|}\)$" -print0)

    if ((${#tmp_array[@]})); then
        check_if_local_index_is_ready "${sphinx_index}" || {
            echo "skipping rotation of local index: ${sphinx_index} ..." | json_logger INFO
            continue
        }

        # remove blank strings from array
        IFS=" " read -r -a new_files_merged <<< ${tmp_array[@]}
        if ((${#new_files_merged[@]})); then
            # start index rotation
            echo "restart searchd for index rotation..." | json_logger INFO
            pkill -1 searchd

            # wait until all files new_files and locally renamed files have been renamed / rotated in SPHINX_VOLUME
            echo "wait for index rotation ${sphinx_index}..." | json_logger INFO
            all_files_are_gone=false
            while ! ${all_files_are_gone}; do
                all_files_are_gone=true
                echo "about to rotate ${sphinx_index}, waiting for ${new_files_merged[*]} to disappear" | json_logger INFO
                for new_file in ${new_files_merged[@]}; do
                    # skip empty elements
                    [[ -z ${new_file} ]] && continue
                    [ -f "${SPHINX_VOLUME}${new_file}" ] && all_files_are_gone=false
                done
                # shellcheck disable=SC2046
                ${all_files_are_gone} || echo "still exist:" $( cd "${SPHINX_VOLUME}"; ls "${new_files_merged[@]}" 2> /dev/null ) | json_logger INFO
                sleep 5
            done
        fi
    fi
done


echo "finished" | json_logger INFO
touch /tmp/last_sync_finished.txt || :
