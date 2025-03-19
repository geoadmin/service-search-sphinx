FROM python:3.9.9-slim-buster as sphinxsearch_base

RUN apt-get update && \
    apt-get install -y \
    cron \
    default-mysql-client \
    gettext-base \
    gosu \
    jq \
    procps \
    rsync \
    sphinxsearch \
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
FROM sphinxsearch_base as sphinxsearch_geodata

    # add geodata user, same uid/gid as the EFS owner is needed here
RUN groupadd -r geodata -g 2500 && \
    useradd -u 2500 -r -g geodata -s /sbin/nologin --create-home geodata && \
    # create mountpoint for Amazon EFS CSI driver
    install -o geodata -g geodata -d /var/local/ && \
    # create mountpoint folder for infra-vhost/k8s ebs/ssd volume
    install -o geodata -g geodata -d /var/lib/sphinxsearch/data/index/ && \
    # change ownerships to geodata which will run the service or the maintenance scripts
    # and mount the efs folder
    chown -R geodata:geodata /var/run/sphinxsearch/ && \
    chown -R geodata:geodata /var/log/sphinxsearch/ && \
    chown -R geodata:geodata /etc/sphinxsearch && \
    # install pip3 psycopg2, python3.9 does not (yet) support python3-psycopg2 package
    gosu geodata pip3 install psycopg2-binary==2.9.2

FROM sphinxsearch_geodata

# Define the build argument with a default value
ARG VERSION="unknown"
# Make the argument available for use in the Dockerfile
ENV VERSION=${VERSION}
# Create the directory if it doesn't exist and save the value of the VERSION argument to /usr/local/share/app/version.txt
RUN mkdir -p /usr/local/share/app && echo "${VERSION}" > /usr/local/share/app/version.txt && chown -R geodata:geodata /usr/local/share/app

ARG GIT_HASH=unknown
ARG GIT_BRANCH=unknown
ARG GIT_DIRTY=""
ARG AUTHOR=unknown
LABEL git.hash=$GIT_HASH
LABEL git.branch=$GIT_BRANCH
LABEL git.dirty="$GIT_DIRTY"
LABEL author=$AUTHOR
LABEL version=$VERSION

# copy sphinxsearch config and maintenance code
COPY --chown=geodata:geodata scripts/docker-* scripts/index-sync-rotate.sh scripts/pg2sphinx_trigger.py scripts/checker.sh /
COPY --chown=geodata:geodata conf /conf/

USER geodata

# default CMD
ENTRYPOINT [ "/docker-entry.sh" ]
# run service with the following script if no CMDs are sent to docker run / default
CMD ["/docker-cmd.sh"]
