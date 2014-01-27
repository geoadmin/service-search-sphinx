#!/bin/bash
SPHINXCONFIG=/etc/sphinxsearch/sphinx.conf
DEPLOYCONFIG=./deploy-conf-only.cfg

usage="
deploy-conf-only.sh
sphinx deploy wrapper script
Deploys the sphinx config to the target, if the optional parameter -d is set, all the index using the defined database pattern will be built.
arguments:
    -t <<DEPLOY TARGET>> mandatory 
        p.e.
        -t ab
        -t prod
    -d <<DATABASE PATTERN>> optional 
        p.e. 
        -d lubis -> all indexes using this database will be built
        -d stopo.public -> all indexes using a table from that schema will be built
        -d bafu.gefahren.gfz -> all indexes using this table will be built
        -d all -> all the indexes will be built
        DEFAULT: none"

if [ ! -f $SPHINXCONFIG ]
then
    echo "no sphinx configuration found in $SPHINXCONFIG -> no deploy"
    exit 0
fi

while getopts "t:d:h" flag
do
  case $flag in
    t)      t_flag=true;
            target=$OPTARG
            if [ -z "$OPTARG" ] || [[ $OPTARG == *"-"* ]]
            then
                echo "$usage"
                exit 0
            fi
            ;;
    d)      database=$OPTARG;;
    h)      echo "$usage"
            exit 0;;
    \? )    echo "$usage"
            exit 1;;
  esac
done
shift $((OPTIND-1))

if [ ! $t_flag ] 
then
    echo "$usage"
    exit 0
fi

if grep dbpattern $DEPLOYCONFIG > /dev/null
then
    echo "dbpattern found in $DEPLOYCONFIG"
    perl -p -i -e "s/(dbpattern[\s]*=)([\w\s\.\-]*)$/\1 $database\n/g" $DEPLOYCONFIG
else
    echo "dbpattern not found in $DEPLOYCONFIG"
    sed -i "s/.*\[env\].*/&\ndbpattern = $database/" $DEPLOYCONFIG
fi

sudo -u deploy deploy -r deploy-conf-only.cfg $target

