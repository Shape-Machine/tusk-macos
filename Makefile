PROJECT = Tusk.xcodeproj
SCHEME  = Tusk
CONFIG  = Debug

BUILD_DIR := $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	-showBuildSettings 2>/dev/null | awk '$$1 == "BUILT_PRODUCTS_DIR" {print $$3}')
APP = $(BUILD_DIR)/$(SCHEME).app

.PHONY: all build clean run generate

all: build

## Generate Xcode project from project.yml
generate:
	xcodegen generate

## Build the app
build:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination "platform=macOS" \
		build

## Clean build artifacts
clean:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		clean

## Build and run (kills any existing instance first)
run: build
	@pkill -x $(SCHEME) 2>/dev/null || true
	@open "$(APP)"
