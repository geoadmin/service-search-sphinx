

.PHONY: help

help:
	@echo "Usage: make <target>"
	@echo
	@echo "Possible targets:"
	@echo
	@echo "- index            Build indices"
	@echo "- template         Create sphinx config file"
	@echo

.PHONY: index
index:
	indexer --verbose --rotate --config etc/sphinxsearch/sphinx.conf  --sighup-each layers_de


.PHONY: template
template:
	sed -e 's/$$PGUSER/$(PGUSER)/' -e 's/$$PGPASS/$(PGPASS)/'  etc/sphinxsearch/sphinx.conf.in  > etc/sphinxsearch/sphinx.conf
