FEATURES_INDICES := $(shell find /var/lib/sphinxsearch/data/index/ -type f -name 'ch_*spa' | sed 's:/var/lib/sphinxsearch/data/index/::' |  sed 's:.spa::')

.PHONY: help
help:
	@echo "Usage: make <target>"
	@echo
	@echo "Possible targets:"
	@echo
	@echo "Indexing only for updates (sudo su sphinxsearch):"
	@echo "- index-all      	Update all indices (does NOT re-create config file)"
	@echo "- index-search		Update swisssearch indices (does NOT re-create config file)"
	@echo "- index-layers      	Update all the layers indices (does NOT re-create config file)"
	@echo "- index-features		Update all the features indices (does NOT re-create config file)"
	@echo
	@echo "Generate configuration template:"
	@echo "- template   		Create sphinx config file from template"
	@echo

.PHONY: index-all
index-all: move-template
	indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each --all

.PHONY: index-search
index-search: move-template
	indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each address parcel sn25 gg25 kantone district zipcode

.PHONY: index-layers
index-layers: move-template
	indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each layers_de layers_fr layers_it layers_en layers_rm

.PHONY: index-features
index-features: move-template
	indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each $(FEATURES_INDICES)

.PHONY: template
template: conf/sphinx.conf.in
	sed -e 's/$$PGUSER/$(PGUSER)/' -e 's/$$PGPASS/$(PGPASS)/'  conf/sphinx.conf.in  > conf/sphinx.conf

.PHONY: move-template
move-template:
	cp conf/sphinx.conf /var/lib/sphinxsearch/data/index/sphinx.conf
