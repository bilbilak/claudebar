APP_NAME  := ClaudeBar
BUNDLE_ID := org.bilbilak.claudebar
CONFIG    := release
APP       := dist/$(APP_NAME).app

.PHONY: build bundle run install codesign clean

build:
	swift build -c $(CONFIG)

bundle: build
	@BUILD_BIN="$$(swift build --show-bin-path -c $(CONFIG))" ; \
	rm -rf $(APP) ; \
	mkdir -p $(APP)/Contents/MacOS ; \
	mkdir -p $(APP)/Contents/Resources ; \
	cp "$$BUILD_BIN/$(APP_NAME)" $(APP)/Contents/MacOS/$(APP_NAME) ; \
	cp Resources/Info.plist $(APP)/Contents/Info.plist ; \
	echo "" ; \
	echo "Bundled -> $(APP)" ; \
	echo "Launch with: open $(APP)"

run: bundle
	open $(APP)

install: bundle
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/$(APP_NAME).app
	@echo "Installed -> /Applications/$(APP_NAME).app"

codesign: bundle
	codesign --force --deep --sign - $(APP)

clean:
	swift package clean
	rm -rf .build dist
