# Makefile env
SHELL = /bin/bash

.DEFAULT_GOAL := help

export SERVICE_NAME := service-sphinxsearch
export STAGING?=dev
export ENV_FILE?=$(STAGING).env

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
export DOCKER_INDEX_VOLUME ?= sphinx_index_$(STAGING)

# git pre-commit hook
GIT_DIR := $(shell git rev-parse --git-dir)
HOOK_DIR := $(GIT_DIR)/hooks

# check if environment file exists
ifneq ("$(wildcard $(ENV_FILE))","")
include ${ENV_FILE}
else
$(error "environment file does not exist ${ENV_FILE}")
endif

# Maintenance / Index Commands
# EFS Index will be mounted as bind mount
export DOCKER_EXEC :=  docker run \
				--rm \
				-t \
				-v $(SPHINX_INDEX):/var/lib/sphinxsearch/data/index/ \
				--name $(DOCKER_LOCAL_TAG)_maintenance \
				$(DOCKER_IMG_LOCAL_TAG)

export DOCKER_EXEC_LOCAL :=  docker run \
				--rm \
				-t \
				-v $(CURRENT_DIR)/conf/:/var/lib/sphinxsearch/data/index/ \
				--name $(DOCKER_LOCAL_TAG)_maintenance \
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
	@echo "- pg2sphinx                 Create / Update indices based on DB or INDEX pattern, EFS index will be synced to docker volumes (does NOT re-create config file)"
	@echo "                            (STAGING=(dev|int|prod) DB= or INDEX= ) p.e. STAGING=dev DB=bod_dev make pg2sphinx"
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
	@echo "- GIT_HASH:                 ${YELLOW}${GIT_HASH}${RESET}"
	@echo "- GIT_HASH_SHORT:           ${YELLOW}${GIT_HASH_SHORT}${RESET}"
	@echo "- GIT_BRANCH:               ${YELLOW}${GIT_BRANCH}${RESET}"
	@echo "- GIT_TAG:                  ${YELLOW}${GIT_TAG}${RESET}"
	@echo "- GIT_DIRTY:                ${YELLOW}${GIT_DIRTY}${RESET}"
	@echo
	@echo "- AUTHOR/USER:              ${YELLOW}${AUTHOR}/${USER}${RESET}"
	@echo "- DOCKER_REGISTRY:          ${YELLOW}${DOCKER_REGISTRY}${RESET}"
	@echo "- DOCKER_LOCAL_TAG:         ${YELLOW}${DOCKER_LOCAL_TAG}${RESET}"
	@echo "- DOCKER_IMG_LOCAL_TAG:     ${YELLOW}${DOCKER_IMG_LOCAL_TAG}${RESET}"
	@echo "- DOCKER_INDEX_VOLUME:      ${YELLOW}${DOCKER_INDEX_VOLUME}${RESET}"
	@echo
	@echo "- STAGING:                  ${YELLOW}${STAGING}${RESET}"
	@echo "- ENV_FILE:                 ${YELLOW}${ENV_FILE}${RESET}"
	@echo "- SPHINX_PORT:              ${YELLOW}${SPHINX_PORT}${RESET}"
	@echo "- SPHINX_INDEX:             ${YELLOW}${SPHINX_INDEX}${RESET}"

.PHONY: pg2sphinx
pg2sphinx:
	export $(shell cat $(ENV_FILE)) && DOCKER_INDEX_VOLUME=$(DOCKER_INDEX_VOLUME) ./scripts/pg2sphinx.sh

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
	cat conf/*.part > conf/sphinx.conf.in
	export $(shell cat $(ENV_FILE)) && envsubst < conf/sphinx.conf.in > conf/sphinx.conf

.PHONY: move-template
move-template: template check-config-local
	cp -a conf/sphinx.conf conf/wordforms_main.txt $(SPHINX_INDEX)

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
		--restart=always \
		-d \
		-p $(SPHINX_PORT):$(SPHINX_PORT) \
		-v $(SPHINX_INDEX):/var/lib/sphinxsearch/data/index_efs/ \
		-v ${DOCKER_INDEX_VOLUME}:/var/lib/sphinxsearch/data/index/ \
		--name $(DOCKER_LOCAL_TAG) \
		$(DOCKER_IMG_LOCAL_TAG)

.PHONY: dockerrundebug
dockerrundebug: dockerbuild
	docker run \
		--rm \
		-it \
		-p $(SPHINX_PORT):$(SPHINX_PORT) \
		-v $(SPHINX_INDEX):/var/lib/sphinxsearch/data/index_efs/ \
		-v ${DOCKER_INDEX_VOLUME}:/var/lib/sphinxsearch/data/index/ \
		--name $(DOCKER_LOCAL_TAG) \
		$(DOCKER_IMG_LOCAL_TAG)


