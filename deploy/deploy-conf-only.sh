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
        -i ch_swisstopo -> all indexes with infix ***ch_swisstopo*** will be built
        -i all -> all the indexes will be built
        DEFAULT: none        
    -c  <<CLEAN INDEX>> [true|false] optional
        p.e.
        -c true -> on the deploy target missing indexes will be created, orphaned indexes will be deleted
        DEFAULT: false 
        "

if [ ! -f $SPHINXCONFIG ]
then
    echo "no sphinx configuration found in $SPHINXCONFIG -> no deploy"
    exit 1
fi

clean_index=false

while getopts "t:d:i:c:h" flag
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
    c)      clean_index=$OPTARG;;
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
    # set value for dbpattern
    perl -p -i -e "s/(dbpattern[\s]*=)([\w\s\.\-]*)$/\1 $database\n/g" $DEPLOYCONFIG
else
    # add dbpattern parameter and set value
    sed -i "s/.*\[env\].*/&\ndbpattern = $database/" $DEPLOYCONFIG
fi

if grep indexpattern $DEPLOYCONFIG > /dev/null
then
    # set value for indexpattern
    perl -p -i -e "s/(indexpattern[\s]*=)(.*)/\1 $index/g" $DEPLOYCONFIG
else
    # add indexpattern parameter and set value
    sed -i "s/.*\[env\].*/&\nindexpattern = $index/" $DEPLOYCONFIG
fi

if grep clean_index $DEPLOYCONFIG > /dev/null
then
    # set value for indexpattern
    perl -p -i -e "s/(clean_index[\s]*=)(.*)/\1 $clean_index/g" $DEPLOYCONFIG
else
    # add indexpattern parameter and set value
    sed -i "s/.*\[env\].*/&\nclean_index = $clean_index/" $DEPLOYCONFIG
fi

if [[ $clean_index = "true" ]];
then
    # disable code section in deploy.cfg for clean index deploy
    sed -r -i '/^\[code\]$/,/^\[/ s/^active ?= ?true/active = false/' $DEPLOYCONFIG
fi 

sudo -u deploy deploy -r deploy-conf-only.cfg $target

# reset dbpattern and indexpattern to null
perl -p -i -e "s/(dbpattern[\s]*=)([\w\s\.\-]*)$/\1 \n/g" $DEPLOYCONFIG
perl -p -i -e "s/(indexpattern[\s]*=)(.*)/\1 /g" $DEPLOYCONFIG
perl -p -i -e "s/(clean_index[\s]*=)(.*)/\1 /g" $DEPLOYCONFIG

if [[ $clean_index = "true" ]];
then
    # enable code section in deploy.cfg for standard config deploy
    sed -r -i '/^\[code\]$/,/^\[/ s/^active ?= ?false/active = true/' $DEPLOYCONFIG
fi 
