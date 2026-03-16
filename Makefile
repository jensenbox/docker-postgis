# Docker PostGIS - Multi-arch Build System
#
# Uses two-level directory structure: <version>/<variant>/Dockerfile
# Each variant directory contains a 'tags' file with space-separated Docker tags.
#
# Configuration via .env file or environment variables:
#   REGISTRY  - Container registry (default: ghcr.io)
#   REPO_NAME - Repository owner (default: jensenbox)
#   IMAGE_NAME - Image name (default: docker-postgis)

-include .env
export

REGISTRY   ?= ghcr.io
REPO_NAME  ?= jensenbox
IMAGE_NAME ?= docker-postgis

DOCKER ?= docker
GIT    ?= git

OFFIMG_LOCAL_CLONE ?= $(HOME)/official-images
OFFIMG_REPO_URL    ?= https://github.com/docker-library/official-images.git

FULL_IMAGE = $(REGISTRY)/$(REPO_NAME)/$(IMAGE_NAME)

# Auto-discover version/variant pairs from filesystem
DOCKERFILE_DIRS := $(sort $(shell find . -mindepth 3 -maxdepth 3 -name Dockerfile -not -path './examples/*' -printf '%h\n' 2>/dev/null | sed 's|^./||'))
VERSIONS := $(sort $(shell echo '$(DOCKERFILE_DIRS)' | tr ' ' '\n' | cut -d'/' -f1 | sort -u))

.DEFAULT_GOAL := help


### GENERATE ###

generate:
	@echo "Generating Dockerfiles from versions.json..."
	./apply-templates.sh

### BUILD ###

define build-target
build-$(1):
	@echo "==> Building $(1) ..."
	$(DOCKER) build --pull \
		$(shell cat $(1)/tags 2>/dev/null | tr ' ' '\n' | sed 's|.*|-t $(FULL_IMAGE):&|' | tr '\n' ' ') \
		$(1)
	@echo "==> Built: $$(cat $(1)/tags 2>/dev/null)"
endef
$(foreach dir,$(DOCKERFILE_DIRS),$(eval $(call build-target,$(dir))))

# Build all
build: $(foreach dir,$(DOCKERFILE_DIRS),build-$(dir))


### TEST ###

test-prepare:
ifeq ("$(wildcard $(OFFIMG_LOCAL_CLONE))","")
	$(GIT) clone $(OFFIMG_REPO_URL) $(OFFIMG_LOCAL_CLONE)
else
	cd $(OFFIMG_LOCAL_CLONE) && $(GIT) pull origin master
endif

define test-target
test-$(1): test-prepare build-$(1)
	@echo "==> Testing $(1) ..."
	$(OFFIMG_LOCAL_CLONE)/test/run.sh \
		-c $(OFFIMG_LOCAL_CLONE)/test/config.sh \
		-c test/postgis-config.sh \
		$(FULL_IMAGE):$$(cat $(1)/tags | cut -d' ' -f1)
endef
$(foreach dir,$(DOCKERFILE_DIRS),$(eval $(call test-target,$(dir))))

# Test all
test: $(foreach dir,$(DOCKERFILE_DIRS),test-$(dir))


### PUSH ###

define push-target
push-$(1): test-$(1)
	@echo "==> Pushing $(1) ..."
	@for tag in $$(cat $(1)/tags); do \
		echo "  push: $(FULL_IMAGE):$$tag"; \
		$(DOCKER) image push $(FULL_IMAGE):$$tag; \
	done
endef
$(foreach dir,$(DOCKERFILE_DIRS),$(eval $(call push-target,$(dir))))

# Push all
push: $(foreach dir,$(DOCKERFILE_DIRS),push-$(dir))


### VERSION CHECK ###

check_version:
	@echo "Checking versions.json..."
	@jq empty versions.json && echo "versions.json is valid JSON" || (echo "ERROR: invalid versions.json" && exit 1)


### LINT ###

lint:
	shellcheck *.sh


### HELP ###

help:
	@echo "Docker PostGIS Multi-Arch Build System"
	@echo ""
	@echo "Registry: $(FULL_IMAGE)"
	@echo ""
	@echo "Targets:"
	@echo "  generate     - Generate Dockerfiles from versions.json"
	@echo "  build        - Build all images"
	@echo "  test         - Test all images"
	@echo "  push         - Push all images"
	@echo "  check_version - Validate versions.json"
	@echo "  lint         - Run shellcheck"
	@echo ""
	@echo "Per-image targets (example for 17-3.5/bullseye):"
	@echo "  build-17-3.5/bullseye"
	@echo "  test-17-3.5/bullseye"
	@echo "  push-17-3.5/bullseye"
	@echo ""
	@echo "Discovered images:"
	@for dir in $(DOCKERFILE_DIRS); do \
		echo "  $$dir  ->  $$(cat $$dir/tags 2>/dev/null)"; \
	done


.PHONY: generate build test test-prepare push check_version lint help \
	$(foreach dir,$(DOCKERFILE_DIRS),build-$(dir)) \
	$(foreach dir,$(DOCKERFILE_DIRS),test-$(dir)) \
	$(foreach dir,$(DOCKERFILE_DIRS),push-$(dir))
