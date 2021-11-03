# Makefile env
SHELL = /bin/bash

.DEFAULT_GOAL := help

export SERVICE_NAME := service-sphinxsearch
export ENV_FILE?=dev.env

CURRENT_DIR := $(shell pwd)
CPUS ?= $(shell grep -c ^processor /proc/cpuinfo)

# Colors
RESET := $(shell tput sgr0)
RED := $(shell tput setaf 1)
GREEN := $(shell tput setaf 2)
YELLOW := $(shell tput setaf 3)
BLUE := $(shell tput setaf 6)
BOLD :=$(shell tput bold)

# Docker metadata dynamic env variables for envsubst etc.
export GIT_HASH ?= $(shell git rev-parse HEAD)
export GIT_HASH_SHORT ?= $(shell git rev-parse --short HEAD)
export GIT_BRANCH ?= $(shell git symbolic-ref HEAD --short 2>/dev/null)
export GIT_DIRTY ?= "$(shell git status --porcelain | head -n 10)"
export GIT_TAG ?= $(shell git describe --tags || echo "no version info")
export AUTHOR ?= $(USER)

# Docker variables dynamic env variables for envsubst etc.
export DOCKER_REGISTRY ?= 974517877189.dkr.ecr.eu-central-1.amazonaws.com
export DOCKER_LOCAL_TAG ?= local-$(USER)-$(GIT_HASH_SHORT)
export DOCKER_IMG_LOCAL_TAG ?= $(DOCKER_REGISTRY)/$(SERVICE_NAME):$(DOCKER_LOCAL_TAG)

# git pre-commit hook
GIT_DIR := $(shell git rev-parse --git-dir)
HOOK_DIR := $(GIT_DIR)/hooks

# check if environment file exists
ifneq ("$(wildcard $(ENV_FILE))","")
include ${ENV_FILE}
else
$(error "environment file does not exist ${ENV_FILE}")
endif

# Commands
DOCKER_EXEC :=  docker run \
				--rm \
				-p ${SPHINX_PORT}:$(SPHINX_PORT) \
				-v $(SPHINX_INDEX):/var/lib/sphinxsearch/data/index/ \
				--name $(DOCKER_LOCAL_TAG) \
				$(DOCKER_IMG_LOCAL_TAG)

DOCKER_EXEC_LOCAL :=  docker run \
				--rm \
				-p ${SPHINX_PORT}:$(SPHINX_PORT) \
				-v $(CURRENT_DIR)/conf/:/var/lib/sphinxsearch/data/index/ \
				--name $(DOCKER_LOCAL_TAG) \
				$(DOCKER_IMG_LOCAL_TAG)


# AWS variables
AWS_DEFAULT_REGION = eu-central-1

INDEX ?= 'Set INDEX variable to specify the index to create'
FEATURES_INDICES := $(shell find $(SPHINX_INDEX) -type f -name 'ch_*spa' | sed 's:$(SPHINX_INDEX)::' |  sed 's:.spa::')
GREP_INDICES := $(shell if [ -f $(SPHINX_INDEX)/sphinx.conf ]; then grep "^index .*$(IPATTERN).*" $(SPHINX_INDEX)/sphinx.conf | sed 's: \: .*::' | grep ".*$(IPATTERN).*" | sed 's:index ::'; fi)

.PHONY: help
help:
	@echo "Usage: make <target>"
	@echo
	@echo "Possible targets:"
	@echo
	@echo "${BOLD}${BLUE}docker targets:${RESET}"
	@echo "- dockerlogin               Login to the AWS ECR registery for pulling/pushing docker images"
	@echo "- dockerbuild               Builds a docker image with the tag ${DOCKER_LOCAL_TAG}"
	@echo "- dockerrun                 Run the docker container on port ${YELLOW}$(SPHINX_PORT)${RESET} with index and config files from ${YELLOW}$(SPHINX_INDEX)${RESET} in background"
	@echo "- dockerrundebug            Run the docker container on port ${YELLOW}$(SPHINX_PORT)${RESET} with index and config files from ${YELLOW}$(SPHINX_INDEX)${RESET} in foreground"

	@echo
	@echo "${BOLD}${BLUE}sphinxsearch targets:${RESET}"
	@echo "- index-all                 Create / Update all indices (does NOT re-create config file)"
	@echo "- index-grep                Update indices that match a given pattern. Pass the pattern as IPATTERN=mypattern directly on the commandline"
	@echo "- index-search              Update swisssearch indices (does NOT re-create config file)"
	@echo "- index-layer               Update all the layers indices (does NOT re-create config file)"
	@echo "- index-feature             Update all the features indices (does NOT re-create config file)"
	@echo "- check-config              Check the sphinx config: ${YELLOW}$(SPHINX_INDEX)sphinx.conf${RESET}"
	@echo "- check-config-local        Check the local sphinx config: ${YELLOW}$(CURRENT_DIR)/conf/sphinx.conf${RESET}"
	@echo "- check-queries-local       Check the queries with the local sphinx config: ${YELLOW}$(CURRENT_DIR)/conf/sphinx.conf${RESET}"
	@echo
	@echo "${BOLD}${BLUE}general targets:${RESET}"
	@echo "- git_hook                  install pre-commit git hook"
	@echo "- template                  Create sphinx config file from template"
	@echo "- move-template             Move local template to final location: ${YELLOW}$(SPHINX_INDEX)${RESET}"
	@echo
	@echo "VARIABLES"
	@echo "-----------"
	@echo "- GIT_HASH:               ${YELLOW}${GIT_HASH}${RESET}"
	@echo "- GIT_HASH_SHORT:         ${YELLOW}${GIT_HASH_SHORT}${RESET}"
	@echo "- GIT_BRANCH:             ${YELLOW}${GIT_BRANCH}${RESET}"
	@echo "- GIT_TAG:                ${YELLOW}${GIT_TAG}${RESET}"
	@echo "- GIT_DIRTY:              ${YELLOW}${GIT_DIRTY}${RESET}"
	@echo
	@echo "- AUTHOR/USER:            ${YELLOW}${AUTHOR}/${USER}${RESET}"
	@echo "- DOCKER_REGISTRY:        ${YELLOW}${DOCKER_REGISTRY}${RESET}"
	@echo "- DOCKER_LOCAL_TAG:       ${YELLOW}${DOCKER_LOCAL_TAG}${RESET}"
	@echo "- DOCKER_IMG_LOCAL_TAG:   ${YELLOW}${DOCKER_IMG_LOCAL_TAG}${RESET}"
	@echo
	@echo "- ENV_FILE:               ${YELLOW}${ENV_FILE}${RESET}"
	@echo "- SPHINX_PORT:            ${YELLOW}${SPHINX_PORT}${RESET}"
	@echo "- SPHINX_INDEX:           ${YELLOW}${SPHINX_INDEX}${RESET}"

.PHONY: index
index:
	$(DOCKER_EXEC) indexer --verbose --rotate  --sighup-each $(INDEX)

.PHONY: index-all
index-all:
	$(DOCKER_EXEC) indexer --verbose --all

.PHONY: index-grep
index-grep:
	$(DOCKER_EXEC) indexer --verbose $(GREP_INDICES)

.PHONY: index-search
index-search:
	$(DOCKER_EXEC) indexer --verbose address parcel gg25 kantone district zipcode swissnames3d haltestellen district_metaphone kantone_metaphone swissnames3d_metaphone swissnames3d_metaphone address_metaphone district_soundex kantone_soundex swissnames3d_soundex haltestellen_soundex address_soundex

.PHONY: index-layer
index-layer:
	$(DOCKER_EXEC) indexer --verbose layers_de layers_fr layers_it layers_en layers_rm

.PHONY: index-feature
index-feature:
	$(DOCKER_EXEC) indexer --verbose --rotate --sighup-each $(FEATURES_INDICES)

.PHONY: check-config
check-config: dockerbuild
	$(DOCKER_EXEC) indextool --checkconfig -c /etc/sphinxsearch/sphinx.conf

.PHONY: check-config-local
check-config-local: dockerbuild template
	$(DOCKER_EXEC_LOCAL) indextool --checkconfig -c /etc/sphinxsearch/sphinx.conf | grep "config valid"
	DOCKER_EXEC_LOCAL="$(DOCKER_EXEC_LOCAL)" ./scripts/check-config-local.sh

.PHONY: git_hook
git_hook:
	cmp -s scripts/pre-commit.sh ${HOOK_DIR}/pre-commit; \
	RETVAL=$$?; \
	if [[ $$RETVAL -ne 0 ]]; then \
		echo "install/update git hook"; \
		mkdir -p ${HOOK_DIR}; \
		cp -f scripts/pre-commit.sh ${HOOK_DIR}/pre-commit && chmod +x ${HOOK_DIR}/pre-commit; \
	fi

.PHONY: template
template:
	@ if [ -z "$(PGPASS)" -o -z "$(PGUSER)" ]; then \
	  echo "ERROR: Environment variables for db connection PGPASS PGUSER  are not set correctly"; exit 2;\
	else true; fi
	sed -e 's/$$PGUSER/$(PGUSER)/' -e 's/$$PGPASS/$(PGPASS)/' -e 's/$$CPUS/$(CPUS)/' conf/db.conf.in  > conf/db.conf
	cat conf/db.conf conf/*.part > conf/sphinx.conf

.PHONY: move-template
move-template: template check-config-local
	cp -a conf/sphinx.conf $(SPHINX_INDEX)

## docker commands
.PHONY: dockerlogin
dockerlogin:
	aws --profile swisstopo-bgdi-builder ecr get-login-password --region $(AWS_DEFAULT_REGION) | docker login --username AWS --password-stdin $(DOCKER_REGISTRY)

.PHONY: dockerbuild
dockerbuild:
	docker build \
		-q \
		--tag $(DOCKER_IMG_LOCAL_TAG) .

.PHONY: dockerrun
dockerrun: dockerbuild
	docker run \
		--rm \
		-d \
		-p $(SPHINX_PORT):$(SPHINX_PORT) \
		-v $(SPHINX_INDEX):/var/lib/sphinxsearch/data/index/ \
		--name $(DOCKER_LOCAL_TAG) \
		$(DOCKER_IMG_LOCAL_TAG)

.PHONY: dockerrundebug
dockerrundebug: dockerbuild
	docker run \
		--rm \
		-p $(SPHINX_PORT):$(SPHINX_PORT) \
		-v $(SPHINX_INDEX):/var/lib/sphinxsearch/data/index/ \
		--name $(DOCKER_LOCAL_TAG) \
		$(DOCKER_IMG_LOCAL_TAG)
