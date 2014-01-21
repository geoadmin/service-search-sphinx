IPATTERN ?= 'Set IPATTERN variable in call'
INDEX ?= 'Set INDEX variable to specify the index to create'
FEATURES_INDICES := $(shell find /var/lib/sphinxsearch/data/index/ -type f -name 'ch_*spa' | sed 's:/var/lib/sphinxsearch/data/index/::' |  sed 's:.spa::')
GREP_INDICES := $(shell if [ -f conf/sphinx.conf ]; then grep "^index .*$(IPATTERN).* : " conf/sphinx.conf | sed 's:index ::' | sed 's: \: .*::'; fi)

.PHONY: help
help:
	@echo "Usage: make <target>"
	@echo
	@echo "Possible targets:"
	@echo
	@echo "Indexing only for updates (sudo su sphinxsearch):"
	@echo "- index-all	Update all indices (does NOT re-create config file)"
	@echo "- index-grep	Update indices that match a given pattern. Pass the pattern as IPATTERN=mypattern directly on the commandline"
	@echo "- index-search	Update swisssearch indices (does NOT re-create config file)"
	@echo "- index-layer	Update all the layers indices (does NOT re-create config file)"
	@echo "- index-feature	Update all the features indices (does NOT re-create config file)"
	@echo "- move-template	Move template to the apropriate locations"
	@echo
	@echo "Generate configuration template:"
	@echo "- template	Create sphinx config file from template"
	@echo
	@echo "Deploy:"
	@echo "- deploy-ab	Deploy all the indices in integration"
	@echo "- deploy-prod	Deploy all the indices in production"

.PHONY: index
index: move-template
	indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each $(INDEX)

.PHONY: index-all
index-all: move-template
	indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each --all

.PHONY: index-grep
index-grep: move-template
	indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each $(GREP_INDICES)

.PHONY: index-search
index-search: move-template
	indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each address parcel sn25 gg25 kantone district zipcode

.PHONY: index-layer
index-layer: move-template
	indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each layers_de layers_fr layers_it layers_en layers_rm

.PHONY: index-feature
index-feature: move-template
	indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each $(FEATURES_INDICES)

.PHONY: template
template:
	sed -e 's/$$PGUSER/$(PGUSER)/' -e 's/$$PGPASS/$(PGPASS)/'  conf/db.conf.in  > conf/db.conf
	cat conf/db.conf conf/*.part > conf/sphinx.conf

.PHONY: deploy-ab
deploy-ab:
	sudo -u deploy deploy  -r deploy/deploy.cfg ab

.PHONY: deploy-prod
deploy-prod:
	sudo -u deploy deploy  -r deploy/deploy.cfg prod

.PHONY: move-template
move-template:
	cp conf/sphinx.conf /var/lib/sphinxsearch/data/index/sphinx.conf
	cp conf/sphinx.conf /etc/sphinxsearch/sphinx.conf
