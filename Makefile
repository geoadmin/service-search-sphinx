# Makefile env
SHELL = /bin/bash

INDEX ?= 'Set INDEX variable to specify the index to create'
GREP_INDICES := $(shell if [ -f conf/sphinx.conf ]; then grep "^index .*$(IPATTERN).*" conf/sphinx.conf | sed 's: \: .*::' | grep ".*$(IPATTERN).*" | sed 's:index ::'; fi)

.PHONY: help
help:
	@echo "Usage: make <target>"
	@echo
	@echo "Possible targets:"
	@echo
	@echo "Indexing only for updates (sudo su sphinxsearch):"
	@echo
	@echo "- index-grep                Update indices that match a given pattern. Pass the pattern as IPATTERN=mypattern directly on the commandline"
	@echo "- index-layer               Update all the layers indices (does NOT re-create config file)"
	@echo "- move-template             Move template to the apropriate locations"
	@echo
	@echo "Generate configuration template:"
	@echo
	@echo "- template                  Create sphinx config file from template"
	@echo
	@echo "Deploy:"
	@echo
	@echo "- deploy-int-config         Deploy the sphinx config only in integration, an optional DB pattern can be indicated db=database.schema.table, all indexes using this DB source will be updated,"
	@echo "                            an optional index pattern can be indicated  index=ch_swisstopo, all indexes with this prefix will be updated.,"
	@echo "- deploy-prod-config        Deploy the sphinx config only in production, an optional DB pattern can be indicated db=database.schema.table, all indexes using this DB source will be updated,"
	@echo "                            an optional index pattern can be indicated  index=ch_swisstopo, all indexes with this prefix will be updated."
	@echo "- deploy-demo-config        Deploy the sphinx config only on a demo instance, an optional DB pattern can be indicated db=database.schema.table, all indexes using this DB source will be updated,"
	@echo "                            an optional index pattern can be indicated  index=ch_swisstopo, all indexes with this praefix will be updated."
	@echo "- deploy-int-clean_index    On the deploy target, new indexes will be generated and orphaned indexes will be deleted"
	@echo "- deploy-prod-clean_index   On the deploy target, new indexes will be generated and orphaned indexes will be deleted"
	@echo "- deploy-demo-clean_index   On the deploy target, new indexes will be generated and orphaned indexes will be deleted"

.PHONY: index
index: move-template
	sudo -u sphinxsearch indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each $(INDEX)

.PHONY: index-grep
index-grep: guard-IPATTERN move-template
	sudo -u sphinxsearch indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each $(GREP_INDICES)

.PHONY: index-layer
index-layer: move-template
	sudo -u sphinxsearch indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each layers_de layers_fr layers_it layers_en layers_rm

scripts/pre-commit.sh:
.git/hooks/pre-commit: scripts/pre-commit.sh
	cp -f $^ $@ && chmod +x $@

.PHONY: template
template: .git/hooks/pre-commit
	@ if [ -z "$$PGPASS" -o -z "$$PGUSER" ]; then \
	  echo "ERROR: Environment variables for db connection PGPASS PGUSER  are not set correctly"; exit 2;\
	else true; fi
	sed -e 's/$$PGUSER/$(PGUSER)/' -e 's/$$PGPASS/$(PGPASS)/'  conf/db.conf.in  > conf/db.conf
	cat conf/db.conf conf/*.part > conf/sphinx.conf
	$(eval CONFIG_VALID=$(shell indextool --checkconfig -c conf/sphinx.conf | grep "config valid"))
	@if [ "${CONFIG_VALID}" = "config valid" ]; then \
	  echo ${CONFIG_VALID}; \
	else echo "Invalid config" && indextool --checkconfig -c conf/sphinx.conf && exit 2; fi

.PHONY: deploy-int-clean_index
deploy-int-clean_index:
	cd deploy && bash deploy-conf-only.sh -t int -c true

.PHONY: deploy-prod-clean_index
deploy-prod-clean_index:
	cd deploy && bash deploy-conf-only.sh -t prod -c true

.PHONY: deploy-demo-clean_index
deploy-demo-clean_index:
	cd deploy && bash deploy-conf-only.sh -t demo -c true

.PHONY: deploy-int-config
deploy-int-config:
ifneq ($(db),)
		cd deploy && bash deploy-conf-only.sh -t int -d $(db)
else ifneq ($(index),)
		cd deploy && bash deploy-conf-only.sh -t int -i $(index)
else
		cd deploy && bash deploy-conf-only.sh -t int
endif

.PHONY: deploy-prod-config
deploy-prod-config:
ifneq ($(db),)
		cd deploy && bash deploy-conf-only.sh -t prod -d $(db)
else ifneq ($(index),)
		cd deploy && bash deploy-conf-only.sh -t prod -i $(index)
else
		cd deploy && bash deploy-conf-only.sh -t prod
endif

.PHONY: deploy-demo-config
deploy-demo-config:
ifneq ($(db),)
		cd deploy && bash deploy-conf-only.sh -t demo -d $(db)
else ifneq ($(index),)
		cd deploy && bash deploy-conf-only.sh -t demo -i $(index)
else
		cd deploy && bash deploy-conf-only.sh -t demo
endif


.PHONY: move-template
move-template:
	bash deploy/move-template.sh

guard-%:
	@ if test "${${*}}" = ""; then \
		echo "Environment variable $* not set. Add it to your command."; \
		exit 1; \
	fi
