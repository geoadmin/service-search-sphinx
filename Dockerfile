FROM debian:buster-slim

RUN apt-get update && \
    apt-get install -y \
    python3 \
    python3-psycopg2 \
    sphinxsearch \
    vim \
    procps \
    rsync \
    default-mysql-client && \
    apt-get clean

# add geodata user, same uid/gid as the EFS owner is needed here
RUN groupadd -r geodata -g 2500 && \
    useradd -u 2500 -r -g geodata -s /sbin/nologin geodata

RUN mkdir -p /var/lib/sphinxsearch/data/index/
RUN mkdir -p /var/lib/sphinxsearch/data/index_efs/

COPY scripts/docker* deploy/pg2sphinx_trigger.py /

# change ownerships to geodata which will run the service or the maintenance scripts
RUN chown -R geodata:geodata /var/lib/sphinxsearch/data/ && \
    chown -R geodata:geodata /var/run/sphinxsearch/ && \
    chown -R geodata:geodata /var/log/sphinxsearch/ && \
    chown -R geodata:geodata /pg2sphinx_trigger.py && \
    chown -R geodata:geodata /docker-* && \
    chown -R geodata:geodata /etc/sphinxsearch/


# start sphinxsearch with geodata user because the indexfiles are persisted to efs
USER geodata

# default CMD
ENTRYPOINT [ "/docker-entry.sh" ]
# run service with the following script if no CMDs are sent to docker run / default
CMD ["/docker-cmd.sh"]
