##@ Project Configuration
# ------------------------------------------------------------------------------
APP_NAME := Lunt
EXECUTABLE_NAME := Lunt
BUILD_DIR := .build
PROJECT_DIR := $(shell pwd)

USER_APPLICATIONS := $(HOME)/Applications
INSTALL_PATH := $(USER_APPLICATIONS)/$(APP_NAME).app
RELEASE_APP = $(shell swift build -c release --triple $(ARCH)-apple-macosx --show-bin-path)/$(APP_NAME).app

GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")

VERSION ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Lunt/Info.plist)
MARKETING_SEMVER := $(VERSION)

BUILD_NUMBER ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Lunt/Info.plist)

ARCH := arm64
DMG_VOLUME_NAME := $(APP_NAME)
DMG_LABEL := Apple Silicon

RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m

##@ General
# ------------------------------------------------------------------------------
.PHONY: help
help: ## Display available commands
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: version
version: ## Show version information
	@echo "Version:      $(VERSION)"
	@echo "Git Commit:   $(GIT_COMMIT)"
	@echo "Marketing:    $(MARKETING_SEMVER)"
	@echo "Build Number: $(BUILD_NUMBER)"

##@ Build AND RUN
# ------------------------------------------------------------------------------
define build_app
	@echo "$(BLUE)🔨 Building $(APP_NAME) ($(1), $(ARCH))...$(NC)"
	swift build -c $(1) --triple $(ARCH)-apple-macosx
	APP_NAME=$(APP_NAME) EXECUTABLE_NAME=$(EXECUTABLE_NAME) VERSION=$(VERSION) BUILD_NUMBER=$(BUILD_NUMBER) ./Scripts/package_app.sh $(1) $(ARCH)
	@echo "$(GREEN)✅ Build completed!$(NC)"
endef

.PHONY: build
build: ## Build for development (debug, Apple Silicon)
	$(call build_app,debug)
	@echo "$(BLUE)📍 Application: $(shell swift build -c debug --triple $(ARCH)-apple-macosx --show-bin-path)/$(APP_NAME).app$(NC)"


.PHONY: run
run: ## Quick run for development
	@./Scripts/compile_and_run.sh debug


##@ Code Quality
# ------------------------------------------------------------------------------
.PHONY: test
test: ## Run all Swift tests
	swift test

.PHONY: lint
lint: ## Run swiftlint
	swiftlint Sources

.PHONY: lint-fix
lint-fix: ## Run swiftlint with auto-fix
	swiftlint --fix Sources

.PHONY: format
format: ## Format code with SwiftFormat
	swiftformat Sources --config .swiftformat

.PHONY: format-check
format-check: ## Check formatting (for CI)
	swiftformat Sources --config .swiftformat --lint

.PHONY: check
check: lint-fix lint format format-check  ## Run all checks

##@ Release
# ------------------------------------------------------------------------------
.PHONY: dmg
dmg: ## Build the Apple Silicon release DMG
	$(call build_app,release)
	@rm -rf "$(BUILD_DIR)/tmp-$(ARCH)"
	@mkdir -p "$(BUILD_DIR)/tmp-$(ARCH)"
	@cp -a "$(RELEASE_APP)" "$(BUILD_DIR)/tmp-$(ARCH)/"
	@ln -s /Applications "$(BUILD_DIR)/tmp-$(ARCH)/Applications"
	hdiutil create -volname "$(DMG_VOLUME_NAME) ($(DMG_LABEL))" \
		-srcfolder "$(BUILD_DIR)/tmp-$(ARCH)" \
		-ov -format UDZO \
		"$(BUILD_DIR)/$(APP_NAME)-$(VERSION)-$(ARCH).dmg"
	@rm -rf "$(BUILD_DIR)/tmp-$(ARCH)"
	@echo ""
	@echo "$(BLUE)===> Created DMG:$(NC)"
	@echo "    - arm64 (Apple Silicon): $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-$(ARCH).dmg"
	@echo ""
	@echo "Note: This DMG is self-signed. Users must approve it in macOS security settings."

##@ Other
# ------------------------------------------------------------------------------
.PHONY: install
install: ## Build release and install to ~/Applications
	$(call build_app,release)
	@mkdir -p $(USER_APPLICATIONS)
	@rm -rf $(INSTALL_PATH)
	@cp -a "$(RELEASE_APP)" "$(INSTALL_PATH)"
	@echo "$(GREEN)✅ Installed to $(INSTALL_PATH)$(NC)"

.PHONY: clean
clean: ## Clean build artifacts
	swift package clean
	rm -rf $(BUILD_DIR)

.DEFAULT_GOAL := help
