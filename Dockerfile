FROM python:3.9.9-slim-buster

RUN apt-get update && \
    apt-get install -y \
    sphinxsearch \
    vim \
    procps \
    rsync \
    cron \
    gettext-base \
    gosu \
    default-mysql-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    gosu nobody true && \
    # set up cron for non root / geodata user
    chmod gu+rw /var/run && \
    chmod gu+s /usr/sbin/cron && \
    # add geodata user, same uid/gid as the EFS owner is needed here
    groupadd -r geodata -g 2500 && \
    useradd -u 2500 -r -g geodata -s /sbin/nologin --create-home geodata && \
    # create mountpoint folders with geodata ownership
    install -o geodata -g geodata -d /var/lib/sphinxsearch/data/index/ && \
    install -o geodata -p geodata -d /var/lib/sphinxsearch/data/index_efs/ && \
    # change ownerships to geodata which will run the service or the maintenance scripts
    # and mount the efs folder
    chown -R geodata:geodata /var/lib/sphinxsearch/data/ && \
    chown -R geodata:geodata /var/run/sphinxsearch/ && \
    chown -R geodata:geodata /var/log/sphinxsearch/ && \
    chown -R geodata:geodata /etc/sphinxsearch && \
    # install pip3 psycopg2, python3.9 does not (yet) support python3-psycopg2 package
    gosu geodata pip3 install psycopg2-binary==2.9.2

COPY --chown=geodata:geodata scripts/docker-* scripts/index-sync-rotate.sh scripts/pg2sphinx_trigger.py /
COPY --chown=geodata:geodata conf /conf/

# default CMD
ENTRYPOINT [ "/docker-entry.sh" ]
# run service with the following script if no CMDs are sent to docker run / default
CMD ["/docker-cmd.sh"]