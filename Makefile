# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

ifeq ($(OS),Windows_NT)
	build_OS := Windows
	NUL = NUL
else
	build_OS := $(shell uname -s 2>/dev/null || echo Unknown)
	NUL = /dev/null
endif

TOOLS_DIR := hack/tools
TOOLS_BIN_DIR := $(TOOLS_DIR)/bin

# Add tooling binaries here and in hack/tools/Makefile
GOLANGCI_LINT := $(TOOLS_BIN_DIR)/golangci-lint
TOOLING_BINARIES := $(GOLANGCI_LINT)

.DEFAULT_GOAL:=help

### GLOBAL ###
ROOT_DIR := $(shell git rev-parse --show-toplevel)

GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)

help: ## display help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
### GLOBAL ###

##### BUILD #####
ifndef BUILD_VERSION
BUILD_VERSION ?= $$(git describe --tags --abbrev=0)
endif
BUILD_SHA ?= $$(git rev-parse --short HEAD)
BUILD_DATE ?= $$(date -u +"%Y-%m-%d")
CONFIG_VERSION ?= $$(echo "$(BUILD_VERSION)" | cut -d "-" -f1)

ifeq ($(strip $(BUILD_VERSION)),)
BUILD_VERSION = dev
endif
CORE_BUILD_VERSION=$$(cat "./hack/CORE_BUILD_VERSION")
NEW_BUILD_VERSION=$$(cat "./hack/NEW_BUILD_VERSION" 2>/dev/null)

LD_FLAGS = -X "github.com/vmware-tanzu-private/core/pkg/v1/cli.BuildDate=$(BUILD_DATE)"
LD_FLAGS += -X "github.com/vmware-tanzu-private/core/pkg/v1/cli.BuildSHA=$(BUILD_SHA)"
LD_FLAGS += -X "github.com/vmware-tanzu-private/core/pkg/v1/cli.BuildVersion=$(BUILD_VERSION)"

ARTIFACTS_DIR ?= ./artifacts

ifeq ($(build_OS), Linux)
XDG_DATA_HOME := ${HOME}/.local/share
SED := sed -i
endif
ifeq ($(build_OS), Darwin)
XDG_DATA_HOME := ${HOME}/Library/ApplicationSupport
SED := sed -i '' -e
endif

export XDG_DATA_HOME

PRIVATE_REPOS="github.com/vmware-tanzu-private/*,github.com/vmware-tanzu/*,github.com/dvonthenen/*"
GO := GOPRIVATE=${PRIVATE_REPOS} go
##### BUILD #####

##### IMAGE #####
OCI_REGISTRY := projects.registry.vmware.com/tce
EXTENSION_NAMESPACE := tanzu-extensions
##### IMAGE #####

##### LINTING TARGETS #####
.PHONY: fmt vet lint mdlint shellcheck staticcheck check
check: fmt lint mdlint shellcheck staticcheck vet

fmt:
	hack/check-format.sh

lint: tools
	$(GOLANGCI_LINT) run -v --timeout=5m

mdlint:
	hack/check-mdlint.sh

shellcheck:
	hack/check-shell.sh

staticcheck:
	hack/check-staticcheck.sh

vet:
	hack/check-vet.sh
##### LINTING TARGETS #####

##### Tooling Binaries
tools: $(TOOLING_BINARIES) ## Build tooling binaries
.PHONY: $(TOOLING_BINARIES)
$(TOOLING_BINARIES):
	make -C $(TOOLS_DIR) $(@F)
##### Tooling Binaries

##### BUILD TARGETS #####
build: build-plugin

build-all: version clean copy-release config-release install-cli install-cli-plugins
build-plugin: version clean-plugin copy-release config-release install-cli-plugins

re-build-all: version install-cli install-cli-plugins
rebuild-plugin: version install-cli-plugins

release: release-env-check build-all gen-metadata package-release

clean: clean-release clean-plugin clean-core

release-env-check:
ifndef GH_ACCESS_TOKEN
	$(error GH_ACCESS_TOKEN is undefined)
endif

# RELEASE MANAGEMENT
version:
	@echo "BUILD_VERSION:" ${BUILD_VERSION}
	@echo "CONFIG_VERSION:" ${CONFIG_VERSION}
	@echo "CORE_BUILD_VERSION:" ${CORE_BUILD_VERSION}
	@echo "NEW_BUILD_VERSION:" ${NEW_BUILD_VERSION}

PHONY: gen-metadata
gen-metadata:
ifeq ($(shell expr $(BUILD_VERSION)), $(shell expr $(CONFIG_VERSION)))
	go run ./hack/release/release.go -tag $(CONFIG_VERSION) -release
	go run ./hack/metadata/metadata.go -tag $(CONFIG_VERSION) -release
else
	go run ./hack/release/release.go
	go run ./hack/metadata/metadata.go -tag $(BUILD_VERSION)
endif

PHONY: copy-release
copy-release:
	mkdir -p ${XDG_DATA_HOME}/tanzu-repository
	cp -f ./hack/config.yaml ${XDG_DATA_HOME}/tanzu-repository/config.yaml

.PHONY: config-release
config-release:
ifeq ($(shell expr $(BUILD_VERSION)), $(shell expr $(CONFIG_VERSION)))
	$(SED) "s/version: latest/version: $(CONFIG_VERSION)/g" ./hack/config.yaml
	$(SED) "s/version: latest/version: $(CONFIG_VERSION)/g" ${XDG_DATA_HOME}/tanzu-repository/config.yaml
endif

# This should only ever be called CI/github-action
PHONY: tag-release
tag-release: version
ifeq ($(shell expr $(BUILD_VERSION)), $(shell expr $(CONFIG_VERSION)))
	go run ./hack/tags/tags.go -tag $(BUILD_VERSION) -release
	BUILD_VERSION=${NEW_BUILD_VERSION} hack/update-tag.sh
else
	go run ./hack/tags/tags.go
	BUILD_VERSION=$(CONFIG_VERSION) hack/update-tag.sh
endif

.PHONY: package-release
package-release:
	CORE_BUILD_VERSION=${CORE_BUILD_VERSION} BUILD_VERSION=${BUILD_VERSION} hack/package-release.sh

clean-release:
	rm -rf ./build
	rm -rf ./metadata
	rm -rf ./offline
# RELEASE MANAGEMENT

# TANZU CLI
.PHONY: build-cli
build-cli: install-cli

.PHONY: install-cli
install-cli:
	BUILD_VERSION=${CORE_BUILD_VERSION} hack/build-tanzu.sh

PHONY: clean-core
clean-core: clean-cli-metadata
	rm -rf /tmp/tce-release

.PHONY: clean-cli-metadata
clean-cli-metadata:
	- rm -rf ${XDG_DATA_HOME}/tanzu-cli/*
# TANZU CLI

# PLUGINS
.PHONY: prep-build-cli
prep-build-cli:
	$(GO) mod download

.PHONY: build-cli-plugins
build-cli-plugins: prep-build-cli
	$(GO) run github.com/vmware-tanzu-private/core/cmd/cli/plugin-admin/builder cli compile --version $(BUILD_VERSION) \
		--ldflags "$(LD_FLAGS)" --path ./cmd/plugin --artifacts ${ARTIFACTS_DIR}
	# $(GO) run ../../vmware-tanzu-private/core/cmd/cli/plugin-admin/builder/main.go cli compile --version $(BUILD_VERSION) \
	# 	--ldflags "$(LD_FLAGS)" --corepath "cmd/cli/tanzu" --target linux_amd64
	# $(GO) run ../../vmware-tanzu-private/core/cmd/cli/plugin-admin/builder/main.go cli compile --version $(BUILD_VERSION) \
	# 	--ldflags "$(LD_FLAGS)" --corepath "cmd/cli/tanzu" --target windows_amd64
	# $(GO) run ../../vmware-tanzu-private/core/cmd/cli/plugin-admin/builder/main.go cli compile --version $(BUILD_VERSION) \
	# 	--ldflags "$(LD_FLAGS)" --corepath "cmd/cli/tanzu" --target darwin_amd64

.PHONY: install-cli-plugins
install-cli-plugins: build-cli-plugins
	TANZU_CLI_NO_INIT=true $(GO) run -ldflags "$(LD_FLAGS)" github.com/vmware-tanzu-private/core/cmd/cli/tanzu \
		plugin install all --local $(ARTIFACTS_DIR)

PHONY: clean-plugin
clean-plugin: clean-plugin-metadata
	rm -rf ${ARTIFACTS_DIR}

.PHONY: clean-plugin-metadata
clean-plugin-metadata:
	- rm -rf ${XDG_DATA_HOME}/tanzu-repository/*
# PLUGINS

# MISC
.PHONY: create-addon
create-addon: ## create the directory structure from a new add-on
	hack/create-addon-dir.sh $(NAME)
# MISC
##### BUILD TARGETS #####

##### IMAGE TARGETS #####
deploy-kapp-controller: ## deploys the latest version of kapp-controller
	kubectl create ns kapp-controller || true
	kubectl --namespace kapp-controller apply -f https://gist.githubusercontent.com/joshrosso/e6f73bee6ade35b1be5280be4b6cb1de/raw/b9f8570531857b75a90c1e961d0d134df13adcf1/kapp-controller-build.yaml

push-packages: ## build and push package templates
	cd addons/packages && for package in *; do\
		printf "\n===> $${package}\n";\
		imgpkg push --bundle $(OCI_REGISTRY)/$${package}-extension-templates:dev --file $${package}/bundle/;\
	done

update-image-lockfiles: ## updates the ImageLock files in each package
	cd addons/packages && for package in *; do\
		printf "\n===> $${package}\n";\
		kbld --file $${package}/bundle --imgpkg-lock-output $${package}/bundle/.imgpkg/images.yml >> /dev/null;\
	done

redeploy-velero: ## delete and redeploy the velero extension
	kubectl --namespace $(EXTENSION_NAMESPACE) --ignore-not-found=true delete app velero
	kubectl apply --filename extensions/velero/extension.yaml

redeploy-gatekeeper: ## delete and redeploy the velero extension
	kubectl -n tanzu-extensions delete app gatekeeper || true
	kubectl apply -f extensions/gatekeeper/extension.yaml

uninstall-contour:
	kubectl --ignore-not-found=true delete namespace projectcontour contour-operator
	kubectl --ignore-not-found=true --namespace $(EXTENSION_NAMESPACE) delete apps contour
	kubectl --ignore-not-found=true delete clusterRoleBinding contour-extension

deploy-contour:
	kubectl apply --filename extensions/contour/extension.yaml

uninstall-knative-serving:
	kubectl --ignore-not-found=true --namespace $(EXTENSION_NAMESPACE) delete apps knative-serving
	kubectl --ignore-not-found=true delete clusterRoleBinding knative-serving-extension
	kubectl --ignore-not-found=true delete service knative-serving-extension

deploy-knative-serving:
	kubectl apply --filename extensions/knative-serving/serviceaccount.yaml
	kubectl apply --filename extensions/knative-serving/clusterrolebinding.yaml
	kubectl apply --filename extensions/knative-serving/extension.yaml

update-knative-serving: ## updates the ImageLock files in each extension
	kbld --file extensions/knative-serving/bundle --imgpkg-lock-output extensions/knative-serving/bundle/.imgpkg/images.yml
	imgpkg push --bundle $(OCI_REGISTRY)/knative-serving-extension-templates:dev --file extensions/knative-serving/bundle/

redeploy-cert-manager: ## delete and redeploy the cert-manager extension
	kubectl --namespace tanzu-extensions delete app cert-manager
	kubectl apply --filename extensions/cert-manager/extension.yaml

update-package-repository-main: ## package and push TCE's main package repo
	imgpkg push -i projects.registry.vmware.com/tce/main:dev -f addons/repos/main
##### IMAGE TARGETS #####
