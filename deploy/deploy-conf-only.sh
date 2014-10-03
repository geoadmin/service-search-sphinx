#!/bin/bash
SPHINXCONFIG=/etc/sphinxsearch/sphinx.conf
SPHINXWORDFORMS=/var/lib/sphinxsearch/data/index/wordforms_*.txt
DEPLOYCONFIG=./deploy-conf-only.cfg

usage="
deploy-conf-only.sh
sphinx deploy wrapper script
Deploys the sphinx config to the target, if the optional parameter -d is set, all the index using the defined database pattern will be built.
arguments:
    -t <<DEPLOY TARGET>> mandatory 
        p.e.
        -t int
        -t prod
    -d <<DATABASE PATTERN>> optional 
        p.e. 
        -d lubis -> all indexes using this database will be built
        -d stopo.public -> all indexes using a table from that schema will be built
        -d bafu.gefahren.gfz -> all indexes using this table will be built
        -d all -> all the indexes will be built
        DEFAULT: none
    -i <<INDEX PATTERN>> optional 
        p.e. 
        -i ch_swisstopo -> all indexes with prefix ch_swisstopo*** will be built
        -i all -> all the indexes will be built
        DEFAULT: none        "

if [ ! -f $SPHINXCONFIG ]
then
    echo "no sphinx configuration found in $SPHINXCONFIG -> no deploy"
    exit 1
fi

while getopts "t:d:i:h" flag
do
  case $flag in
    t)      t_flag=true;
            target=$OPTARG
            if [ -z "$OPTARG" ] || [[ $OPTARG == *"-"* ]]
            then
                echo "$usage"
                exit 1
            fi
            ;;
    d)      database=$OPTARG;;
    i)      index=$OPTARG;;
    h)      echo "$usage"
            exit 0;;
    \? )    echo "$usage"
            exit 0;;
  esac
done
shift $((OPTIND-1))

if [ ! $t_flag ] 
then
    echo "$usage"
    exit 0
fi

if [ $index ] && [ $database ]
then
    echo "ERROR: use either -d or -i argument"
    echo "$usage"
    exit 1
fi


if grep dbpattern $DEPLOYCONFIG > /dev/null
then
    echo "dbpattern found in $DEPLOYCONFIG"
    perl -p -i -e "s/(dbpattern[\s]*=)([\w\s\.\-]*)$/\1 $database\n/g" $DEPLOYCONFIG
else
    echo "dbpattern not found in $DEPLOYCONFIG"
    sed -i "s/.*\[env\].*/&\ndbpattern = $database/" $DEPLOYCONFIG
fi

if grep indexpattern $DEPLOYCONFIG > /dev/null
then
    echo "indexpattern found in $DEPLOYCONFIG"
    perl -p -i -e "s/(indexpattern[\s]*=)(.*)/\1 $index/g" $DEPLOYCONFIG
else
    echo "indexpattern not found in $DEPLOYCONFIG"
    sed -i "s/.*\[env\].*/&\nindexpattern = $index/" $DEPLOYCONFIG
fi


sudo -u deploy deploy -r deploy-conf-only.cfg $target

