VERSION := $(shell tr -d '[:space:]' < VERSION)
APP     := build/MenuBarClear.app
ZIP     := build/MenuBarClear-$(VERSION).zip
DMG     := build/MenuBarClear-$(VERSION).dmg

.PHONY: all app install uninstall run dmg zip clean

all: app

## Build build/MenuBarClear.app (ARCHS="arm64 x86_64" for a universal build)
app:
	@./scripts/build.sh

## Build and install into /Applications, then launch
install: app
	@./scripts/install.sh

## Remove the app, its settings and its permissions
uninstall:
	@./scripts/uninstall.sh

## Build and launch from the build folder
run: app
	@pkill -x MenuBarClear 2>/dev/null || true
	@open $(APP)

## Build the drag-to-install disk image (release download)
dmg: app
	@./scripts/make-dmg.sh

## Build a plain zip of the app
zip: app
	@rm -f $(ZIP)
	@ditto -c -k --keepParent $(APP) $(ZIP)
	@shasum -a 256 $(ZIP)

clean:
	@rm -rf build
