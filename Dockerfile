FROM debian:buster-slim

RUN apt-get update && \
    apt-get install -y \
    python3 \
    python3-psycopg2 \
    sphinxsearch \
    vim && \
    apt-get clean

# add geodata user, same uid/gid as the EFS owner is needed here
RUN groupadd -r geodata -g 2500 && \
    useradd -u 2500 -r -g geodata -s /sbin/nologin geodata
RUN mkdir -p /var/lib/sphinxsearch/data/index/

# change ownerships to geodata which will run the service
RUN chown -R geodata:geodata /var/lib/sphinxsearch/data/ && \
    chown -R geodata:geodata /var/run/sphinxsearch/ && \
    chown -R geodata:geodata /var/log/sphinxsearch/ && \
    chown -R geodata:geodata /etc/sphinxsearch/

COPY scripts/docker* deploy/pg2sphinx_trigger.py /

# start sphinxsearch with geodata user because the indexfiles are persisted to efs
USER geodata

# default CMD
ENTRYPOINT [ "/docker-entry.sh" ]
CMD ["/docker-cmd.sh"]
