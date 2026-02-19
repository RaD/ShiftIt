SHELL := /bin/bash

APP_NAME := ShiftItGo
BUILD_DIR := build
BIN := $(BUILD_DIR)/$(APP_NAME)
BIN_ARM64 := $(BUILD_DIR)/$(APP_NAME)-arm64
BIN_AMD64 := $(BUILD_DIR)/$(APP_NAME)-amd64
BUNDLE_DIR := $(BUILD_DIR)/$(APP_NAME).app
ARCH := $(shell uname -m)
ARCH_BIN := $(if $(filter arm64,$(ARCH)),$(BIN_ARM64),$(BIN_AMD64))
MACOSX_DEPLOYMENT_TARGET_AMD64 ?= 10.13
MACOSX_DEPLOYMENT_TARGET_ARM64 ?= 11.0
CGO_MIN_FLAGS_AMD64 := -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET_AMD64)
CGO_MIN_FLAGS_ARM64 := -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET_ARM64)
PLIST := Info.plist
ICON_SRC := resources/ShiftIt.icns
ICON_NAME := ShiftIt.icns
MENU_ICON_SRC := resources/ShiftItMenuIcon.png
MENU_ICON_NAME := ShiftItMenuIcon.png
DEFAULTS_SRC := resources/ShiftIt-defaults.plist
DEFAULTS_NAME := ShiftIt-defaults.plist
GOCACHE_DIR := $(BUILD_DIR)/.gocache
GOCACHE_DIR_ABS := $(CURDIR)/$(GOCACHE_DIR)

all: help

help:
	@printf "\nMain make targets:\n"
	@printf "  make app       - Build universal macOS binary (%s)\n" "$(BIN)"
	@printf "  make bundle    - Build .app bundle (%s)\n" "$(BUNDLE_DIR)"
	@printf "  make bundle-arm64 - Build arm64 .app bundle\n"
	@printf "  make bundle-amd64 - Build amd64 .app bundle\n"
	@printf "  make dmg-arm64 - Build arm64 .dmg installer\n"
	@printf "  make dmg-amd64 - Build amd64 .dmg installer\n"
	@printf "  make verify-minos - Show min OS versions for built binaries\n"
	@printf "  make install   - Install app bundle to /Applications\n"
	@printf "  make install-arm64 - Install arm64 app bundle to /Applications\n"
	@printf "  make install-amd64 - Install amd64 app bundle to /Applications\n"
	@printf "  make uninstall - Remove app bundle from /Applications\n"
	@printf "  make arm64     - Build macOS arm64 binary (%s)\n" "$(BIN_ARM64)"
	@printf "  make amd64     - Build macOS amd64 binary (%s)\n" "$(BIN_AMD64)"
	@printf "  make run       - Run universal binary\n"
	@printf "  make sign      - Ad-hoc sign app bundle (%s)\n" "$(BUNDLE_DIR)"
	@printf "  make clean     - Remove build artifacts\n\n"

prep:
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(GOCACHE_DIR_ABS)

arm64: prep
	@echo "Build macOS arm64"
	@GOCACHE=$(GOCACHE_DIR_ABS) CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 CGO_CFLAGS="$(CGO_MIN_FLAGS_ARM64)" CGO_LDFLAGS="$(CGO_MIN_FLAGS_ARM64)" go build -o $(BIN_ARM64) ./src

amd64: prep
	@echo "Build macOS amd64"
	@GOCACHE=$(GOCACHE_DIR_ABS) CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 CGO_CFLAGS="$(CGO_MIN_FLAGS_AMD64)" CGO_LDFLAGS="$(CGO_MIN_FLAGS_AMD64)" go build -o $(BIN_AMD64) ./src

app: arm64 amd64
	@echo "Create universal binary"
	@lipo -create -output $(BIN) $(BIN_ARM64) $(BIN_AMD64)

bundle: app
	@echo "Create app bundle"
	@mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	@mkdir -p $(BUNDLE_DIR)/Contents/Resources
	@cp $(BIN) $(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)
	@cp $(PLIST) $(BUNDLE_DIR)/Contents/Info.plist
	@cp $(ICON_SRC) $(BUNDLE_DIR)/Contents/Resources/$(ICON_NAME)
	@cp $(MENU_ICON_SRC) $(BUNDLE_DIR)/Contents/Resources/$(MENU_ICON_NAME)
	@cp $(DEFAULTS_SRC) $(BUNDLE_DIR)/Contents/Resources/$(DEFAULTS_NAME)

bundle-arm64: arm64
	@echo "Create arm64 app bundle"
	@mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	@mkdir -p $(BUNDLE_DIR)/Contents/Resources
	@cp $(BIN_ARM64) $(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)
	@cp $(PLIST) $(BUNDLE_DIR)/Contents/Info.plist
	@cp $(ICON_SRC) $(BUNDLE_DIR)/Contents/Resources/$(ICON_NAME)
	@cp $(MENU_ICON_SRC) $(BUNDLE_DIR)/Contents/Resources/$(MENU_ICON_NAME)
	@cp $(DEFAULTS_SRC) $(BUNDLE_DIR)/Contents/Resources/$(DEFAULTS_NAME)

bundle-amd64: amd64
	@echo "Create amd64 app bundle"
	@mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	@mkdir -p $(BUNDLE_DIR)/Contents/Resources
	@cp $(BIN_AMD64) $(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)
	@cp $(PLIST) $(BUNDLE_DIR)/Contents/Info.plist
	@cp $(ICON_SRC) $(BUNDLE_DIR)/Contents/Resources/$(ICON_NAME)
	@cp $(MENU_ICON_SRC) $(BUNDLE_DIR)/Contents/Resources/$(MENU_ICON_NAME)
	@cp $(DEFAULTS_SRC) $(BUNDLE_DIR)/Contents/Resources/$(DEFAULTS_NAME)

run: bundle
	@echo "Reset Accessibility permissions"
	@tccutil reset Accessibility com.halfakop.shiftit-go || true
	@echo "Ad-hoc sign app bundle"
	@codesign --force --deep --sign - $(BUNDLE_DIR)
	@echo "Run"
	@open $(BUNDLE_DIR) --args --debug

sign: bundle
	@echo "Ad-hoc sign app bundle"
	@codesign --force --deep --sign - $(BUNDLE_DIR)

sign-arm64: bundle-arm64
	@echo "Ad-hoc sign app bundle (arm64)"
	@codesign --force --deep --sign - $(BUNDLE_DIR)

sign-amd64: bundle-amd64
	@echo "Ad-hoc sign app bundle (amd64)"
	@codesign --force --deep --sign - $(BUNDLE_DIR)

install: sign-$(ARCH)
	@echo "Reset Accessibility permissions"
	@tccutil reset Accessibility com.halfakop.shiftit-go || true
	@echo "Install app bundle"
	@cp -R $(BUNDLE_DIR) /Applications/

install-arm64: sign-arm64
	@echo "Reset Accessibility permissions"
	@tccutil reset Accessibility com.halfakop.shiftit-go || true
	@echo "Install app bundle (arm64)"
	@cp -R $(BUNDLE_DIR) /Applications/

install-amd64: sign-amd64
	@echo "Reset Accessibility permissions"
	@tccutil reset Accessibility com.halfakop.shiftit-go || true
	@echo "Install app bundle (amd64)"
	@cp -R $(BUNDLE_DIR) /Applications/

uninstall:
	@echo "Remove app bundle"
	@rm -rf /Applications/$(APP_NAME).app

dmg-arm64: sign-arm64
	@echo "Create arm64 dmg"
	@hdiutil create -volname $(APP_NAME) -srcfolder $(BUNDLE_DIR) -ov -format UDZO $(BUILD_DIR)/$(APP_NAME)-arm64.dmg

dmg-amd64: sign-amd64
	@echo "Create amd64 dmg"
	@hdiutil create -volname $(APP_NAME) -srcfolder $(BUNDLE_DIR) -ov -format UDZO $(BUILD_DIR)/$(APP_NAME)-amd64.dmg

verify-minos:
	@echo "Min OS versions (if binaries exist):"
	@for f in $(BIN_ARM64) $(BIN_AMD64) $(BIN) $(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME); do \
		if [ -f $$f ]; then \
			printf "  %s: " "$$f"; \
			otool -l "$$f" | awk '/LC_VERSION_MIN_MACOSX/{flag=1} /LC_BUILD_VERSION/{flag=1} flag && /version|minos/{print $$2; flag=0}'; \
		fi; \
	done

clean:
	@echo "Clean"
	@rm -rf $(BUILD_DIR)

.PHONY: help prep arm64 amd64 app bundle bundle-arm64 bundle-amd64 run sign sign-arm64 sign-amd64 install install-arm64 install-amd64 uninstall dmg-arm64 dmg-amd64 verify-minos clean
