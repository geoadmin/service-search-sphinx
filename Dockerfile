FROM manticoresearch/manticore:5.0.2 as manticore_base

RUN apt-get update && \
    apt-get install -y \
    cron \
    gettext \
    libpq-dev \
    manticore-converter \
    python3-pip \
    rsync \
    jq \
    vim && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    gosu nobody true && \
    # set up cron for non root user
    chmod gu+rw /var/run && \
    chmod gu+s /usr/sbin/cron &&\
    mkfifo /tmp/stdout /tmp/stderr && \
    chmod 0666 /tmp/stdout /tmp/stderr

# set up geodata, file permissions, copy files and run container as geodata
FROM manticore_base as manticore_geodata

# add geodata user, same uid/gid as the EFS owner is needed here
RUN groupadd -r geodata -g 2500 && \
    useradd -u 2500 -r -g geodata -s /sbin/nologin --create-home geodata && \
    # create mountpoint folders with geodata ownership

    install -o geodata -g geodata -d /var/lib/manticore/data/index/ && \
    install -o geodata -p geodata -d /var/lib/manticore/data/index_efs/ && \
    
    # change ownerships to geodata which will run the service or the maintenance scripts
    # and mount the efs folder
    chown -R geodata:geodata /var/run/manticore/ && \
    chown -R geodata:geodata /var/log/manticore/ && \
    chown -R geodata:geodata /etc/manticoresearch && \
    chown -R geodata:geodata /var/run/mysqld && \
    # install pip3 psycopg2, python3.9 does not (yet) support python3-psycopg2 package
    gosu geodata pip3 install psycopg2-binary==2.9.2

FROM manticore_geodata

# copy sphinxsearch config and maintenance code
COPY --chown=geodata:geodata scripts/docker-* scripts/index-sync-rotate.sh scripts/pg2sphinx_trigger.py scripts/checker.sh /
COPY --chown=geodata:geodata conf /conf/

USER geodata

WORKDIR /

# default CMD
ENTRYPOINT [ "/docker-entry.sh" ]
# run service with the following script if no CMDs are sent to docker run / default
CMD ["/docker-cmd.sh"]
