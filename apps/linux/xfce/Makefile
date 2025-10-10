.PHONY: build install uninstall clean i18n

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)

build:
	@test -d build || meson setup build --buildtype=release
	meson compile -C build

install: build
	meson install -C build

uninstall:
	@[ -d build ] && meson install -C build --dry-run | awk '/Installing/ {print $$NF}' | xargs -r sudo rm -f || true

clean:
	rm -rf build

i18n:
	@if command -v python3 >/dev/null 2>&1; then \
	    (cd "$(REPO_ROOT)" && python3 scripts/regenerate-translations.py xfce); \
	elif command -v nix-shell >/dev/null 2>&1; then \
	    (cd "$(REPO_ROOT)" && nix-shell -p 'python3.withPackages (ps: [ps.pyyaml])' --run 'python3 scripts/regenerate-translations.py xfce'); \
	else \
	    echo "error: neither python3 nor nix-shell is on PATH" >&2; \
	    exit 1; \
	fi
