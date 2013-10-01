
SED_RULE := 's/$$PGUSER/$(PGUSER)/'

.PHONY: help

help:
	@echo "Usage: make <target>"
	@echo
	@echo "Possible targets:"
	@echo
	@echo "- index            Build indices"

.PHONY: index
index:	echo 'toto'


.PHONY: template
template:
	sed -e 's/$$PGUSER/$(PGUSER)/' -e 's/$$PGPASS/$(PGPASS)/'  etc/sphinxsearch/sphinx.conf.in  > etc/sphinxsearch/sphinx.conf
