

.PHONY: help

help:
	@echo "Usage: make <target>"
	@echo
	@echo "Possible targets:"
	@echo
	@echo "- index      Build indices (does NOT re-create config file)"
	@echo "             Do 'sudo su sphinxsearch' before using this"
	@echo "- template   Create sphinx config file from template"
	@echo

.PHONY: index
index:
	indexer --verbose --rotate --config conf/sphinx.conf  --sighup-each --all
	cp conf/sphinx.conf /var/lib/sphinxsearch/data/index/sphinx.conf

.PHONY: template
template: conf/sphinx.conf.in
	sed -e 's/$$PGUSER/$(PGUSER)/' -e 's/$$PGPASS/$(PGPASS)/'  conf/sphinx.conf.in  > conf/sphinx.conf

