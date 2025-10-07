APP_NAME  := ClaudeBar
BUNDLE_ID := org.bilbilak.claudebar
CONFIG    := release
APP       := dist/$(APP_NAME).app
ARCHES    := --arch arm64 --arch x86_64
REPO_ROOT := ../..

.PHONY: build bundle run install codesign clean i18n

build:
	swift build -c $(CONFIG) $(ARCHES)

i18n:
	@cd $(REPO_ROOT) && ( \
		python3 scripts/regenerate-translations.py macos \
		|| nix-shell -p 'python3.withPackages (ps: [ps.pyyaml])' \
			--run 'python3 scripts/regenerate-translations.py macos' \
	)

bundle: build
	@BUILD_BIN="$$(swift build --show-bin-path -c $(CONFIG) $(ARCHES))" ; \
	rm -rf $(APP) ; \
	mkdir -p $(APP)/Contents/MacOS ; \
	mkdir -p $(APP)/Contents/Resources ; \
	cp "$$BUILD_BIN/$(APP_NAME)" $(APP)/Contents/MacOS/$(APP_NAME) ; \
	cp Resources/Info.plist $(APP)/Contents/Info.plist ; \
	iconutil --convert icns Resources/AppIcon.iconset -o $(APP)/Contents/Resources/AppIcon.icns ; \
	if [ -d "$$BUILD_BIN/$(APP_NAME)_$(APP_NAME).bundle" ]; then \
		cp -R "$$BUILD_BIN/$(APP_NAME)_$(APP_NAME).bundle" $(APP)/Contents/Resources/ ; \
	elif [ -d "$$BUILD_BIN/$(APP_NAME).bundle" ]; then \
		cp -R "$$BUILD_BIN/$(APP_NAME).bundle" $(APP)/Contents/Resources/ ; \
	fi ; \
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
