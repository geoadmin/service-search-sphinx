# Makefile env
SHELL=/bin/bash

.DEFAULT_GOAL := help

export SERVICE_NAME := service-search-sphinx
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

# general targets timestamps
REQUIREMENTS := $(PIP_FILE) $(PIP_FILE_LOCK)

# Find all python files that are not inside a hidden directory (directory starting with .)
PYTHON_FILES := $(shell find ./* -type f -name "*.py" -print)

# Find all bash files that are not inside a hidden directory (directory starting with .)
BASH_FILES := $(shell find ./* -type f -name "*.sh" -print)

# PIPENV files
PIP_FILE = Pipfile
PIP_FILE_LOCK = Pipfile.lock

# Docker variables dynamic env variables for envsubst etc.
export DOCKER_REGISTRY ?= 974517877189.dkr.ecr.eu-central-1.amazonaws.com
export DOCKER_LOCAL_TAG ?= local-$(USER)-$(GIT_HASH_SHORT)
export DOCKER_IMG_LOCAL_TAG ?= $(DOCKER_REGISTRY)/$(SERVICE_NAME):$(DOCKER_LOCAL_TAG)
export DOCKER_INDEX_VOLUME ?= sphinx_index_$(STAGING)

# git pre-commit hook
GIT_DIR := $(shell git rev-parse --git-dir)
HOOK_DIR := $(GIT_DIR)/hooks

# Commands
PIPENV_RUN := pipenv run
PYTHON := $(PIPENV_RUN) python3
PIP := $(PIPENV_RUN) pip3
YAPF := $(PIPENV_RUN) yapf
ISORT := $(PIPENV_RUN) isort
PYLINT := $(PIPENV_RUN) pylint
SHELLCHECK := $(PIPENV_RUN) shellcheck

# check if environment file exists
ifneq ("$(wildcard $(ENV_FILE))","")
include ${ENV_FILE}
else
$(error "environment file does not exist ${ENV_FILE}")
endif

# check db access
DB_ACCESS := $(shell pg_isready -h ${PGHOST} &> /dev/null && echo true || echo false)
ifeq ($(DB_ACCESS),false)
$(warning ${RED}we need a valid postgres connection for this correct use of makefile! connection to '$(PGHOST)' was not successful${RESET})
endif

PPID := $(shell echo $$PPID)

# Maintenance / Index Commands
# EFS Index will be mounted as bind mount
# DOCKER_EXEC will always check if a newer image exists on ecr -> develop.latest support
export DOCKER_EXEC :=  docker run \
				--rm \
				-t \
				--pull=always \
				-v $(SPHINX_EFS):/var/lib/sphinxsearch/data/index/ \
				--env-file $(ENV_FILE) \
				--name $(DOCKER_LOCAL_TAG)_maintenance_$(PPID)\
				$(DOCKER_IMG_LOCAL_TAG)

export DOCKER_EXEC_LOCAL :=  docker run \
				--rm \
				-t \
				-v $(CURRENT_DIR)/conf/:/var/lib/sphinxsearch/data/index/ \
				--env-file $(ENV_FILE) \
				--name $(DOCKER_LOCAL_TAG)_maintenance_$(PPID) \
				$(DOCKER_IMG_LOCAL_TAG)

# AWS variables
AWS_DEFAULT_REGION = eu-central-1

# Set INDEX variable to specify the index or index prefix to create
INDEX ?=
# Set DB variable to specify the database pattern for the index creation
DB ?=

.PHONY: help
help:
	@echo "Usage: make <target>"
	@echo
	@echo "Possible targets:"
	@echo
	@echo "${BOLD}${BLUE}Setup TARGETS${RESET}"
	@echo "- setup                     Create the python virtual environment and activate it"
	@echo "- dev                       Create the python virtual environment with developper tools and activate it"
	@echo "- ci                        Create the python virtual environment and install requirements based on the Pipfile.lock"
	@echo
	@echo "${BOLD}${BLUE}Formating, linting targets${RESET}"
	@echo "- format                    Format the python source code"
	@echo "- ci-check-format           Format the python source code and check if any files has changed. This is meant to be used by the CI."
	@echo "- lint                      Lint the python source code"
	@echo "- shellcheck                shellcheck all the bash scripts"
	@echo "- format-lint               Format and lint the python source code"
	@echo "- test                      Run the tests"
	@echo
	@echo "${BOLD}${BLUE}docker targets:${RESET}"
	@echo "- dockerlogin               Login to the AWS ECR registery for pulling/pushing docker images"
	@echo "- dockerbuild               Builds a docker image with the tag ${YELLOW}${DOCKER_LOCAL_TAG}${RESET}"
	@echo "- dockerpush                Push the docker local image ${YELLOW}${DOCKER_LOCAL_TAG}${RESET} to AWS ECR registry"
	@echo "- dockerrun                 Run the docker container on port ${YELLOW}$(SPHINX_PORT)${RESET} with index and config files from ${YELLOW}$(SPHINX_EFS)${RESET} in background"
	@echo "- dockerrundebug            Run the docker container on port ${YELLOW}$(SPHINX_PORT)${RESET} with index and config files from ${YELLOW}$(SPHINX_EFS)${RESET} in foreground"
	@echo
	@echo "${BOLD}${BLUE}sphinxsearch config and index creation targets:${RESET}"
	@echo "- pg2sphinx                 Create / Update indices based on DB or INDEX pattern, EFS index will be synced to docker volumes (does NOT re-create config file)"
	@echo "                            (STAGING=(dev|int|prod) DB= or INDEX= ) p.e. STAGING=dev DB=bod_dev make pg2sphinx"
	@echo "- check-config-local        build and check the local sphinx config: ${YELLOW}$(CURRENT_DIR)/conf/sphinx.conf${RESET} and the queries"
	@echo
	@echo "${BOLD}${BLUE}general targets:${RESET}"
	@echo "- git_hook                  install pre-commit git hook"
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
	@echo "- SPHINX_EFS:               ${YELLOW}${SPHINX_EFS}${RESET}"
	@echo
	@echo "- CPUS:                     ${YELLOW}${CPUS}${RESET}"
	@echo "- DB_ACCESS:                ${YELLOW}${DB_ACCESS}${RESET}"


# Build targets. Calling setup is all that is needed for the local files to be installed as needed.

.PHONY: dev
dev: $(REQUIREMENTS)
	pipenv install --dev
	pipenv shell


.PHONY: setup
setup: $(REQUIREMENTS)
	pipenv install
	pipenv shell


.PHONY: ci
ci: $(REQUIREMENTS)
	# Create virtual env with all packages for development using the Pipfile.lock
	pipenv sync --dev


# linting target, calls upon yapf to make sure your code is easier to read and respects some conventions.

.PHONY: format
format:
	$(YAPF) -p -i --style .style.yapf $(PYTHON_FILES)
	$(ISORT) $(PYTHON_FILES)


.PHONY: ci-check-format
ci-check-format: format
	@if [[ -n `git status --porcelain --untracked-files=no` ]]; then \
		>&2 echo "ERROR: the following files are not formatted correctly"; \
		>&2 echo "'git status --porcelain' reported changes in those files after a 'make format' :"; \
		>&2 git status --porcelain --untracked-files=no; \
		exit 1; \
	fi


.PHONY: lint
lint:
	$(PYLINT) $(PYTHON_FILES)


.PHONY: format-lint
format-lint: format lint


.PHONY: shellcheck
shellcheck:
	$(SHELLCHECK) $(BASH_FILES)


.PHONY: pg2sphinx
pg2sphinx: load_env $(SPHINX_EFS)
ifndef INDEX
ifndef DB
	@echo "you have to set INDEX or DB variable for this target"
	false
endif
endif
	./scripts/pg2sphinx.sh

.PHONY: check-config-local
check-config-local: dockerbuild config
	$(DOCKER_EXEC_LOCAL) indextool --checkconfig -c /etc/sphinxsearch/sphinx.conf | grep "config valid" || $(DOCKER_EXEC_LOCAL) indextool --checkconfig -c /etc/sphinxsearch/sphinx.conf
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


.PHONY: config
config: load_env
	cat conf/*.part > conf/sphinx.conf.in
	envsubst < conf/sphinx.conf.in > conf/sphinx.conf


## docker commands
.PHONY: dockerlogin
dockerlogin:
	aws --profile swisstopo-bgdi-builder ecr get-login-password --region $(AWS_DEFAULT_REGION) | docker login --username AWS --password-stdin $(DOCKER_REGISTRY)


.PHONY: dockerbuild
dockerbuild:
	docker build \
		-q \
		--build-arg GIT_HASH="${GIT_HASH}" \
		--build-arg GIT_BRANCH="${GIT_BRANCH}" \
		--build-arg VERSION="${GIT_TAG}" \
		--build-arg AUTHOR="${AUTHOR}" \
		--tag $(DOCKER_IMG_LOCAL_TAG) .


.PHONY: dockerpush
dockerpush: dockerbuild
	docker push $(DOCKER_IMG_LOCAL_TAG)


define load_env
	@echo " - load env file $(ENV_FILE)"
	$(eval include $(ENV_FILE))
	$(eval export)
endef


load_env:
	$(call load_env)


# mount folder has to be created first, otherwise docker is creating the folder with root ownership
sphinx_efs: $(SPHINX_EFS)

$(SPHINX_EFS): load_env
	@echo "create folder $@ if it does not yet exist"
	mkdir -p $@

.PHONY: dockerrun
dockerrun: dockerbuild sphinx_efs
	docker run \
		--restart=always \
		-d \
		-p $(SPHINX_PORT):$(SPHINX_PORT) \
		-v $(SPHINX_EFS):/var/lib/sphinxsearch/data/index_efs/ \
		-v ${DOCKER_INDEX_VOLUME}:/var/lib/sphinxsearch/data/index/ \
		--env-file $(ENV_FILE) \
		--name $(DOCKER_LOCAL_TAG) \
		$(DOCKER_IMG_LOCAL_TAG)


.PHONY: dockerrundebug
dockerrundebug: dockerbuild sphinx_efs
	docker run \
		--rm \
		-it \
		-p $(SPHINX_PORT):$(SPHINX_PORT) \
		-v $(SPHINX_EFS):/var/lib/sphinxsearch/data/index_efs/ \
		-v ${DOCKER_INDEX_VOLUME}:/var/lib/sphinxsearch/data/index/ \
		--env-file $(ENV_FILE) \
		--name $(DOCKER_LOCAL_TAG) \
		$(DOCKER_IMG_LOCAL_TAG)
