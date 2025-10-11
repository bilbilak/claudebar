.PHONY: build install uninstall clean i18n

REPO_ROOT := $(abspath $(CURDIR)/../../..)

build:
	@test -d build || meson setup build --buildtype=release
	meson compile -C build

install: build
	sudo meson install -C build

uninstall:
	@[ -d build ] && sudo meson install -C build --dry-run | awk '/Installing/ {print $$NF}' | xargs -r sudo rm -f || true

clean:
	rm -rf build

i18n:
	@if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then \
	    python3 $(REPO_ROOT)/scripts/regenerate-translations.py budgie; \
	elif command -v nix-shell >/dev/null 2>&1; then \
	    nix-shell -p 'python3.withPackages (ps: [ps.pyyaml])' \
	        --run 'python3 $(REPO_ROOT)/scripts/regenerate-translations.py budgie'; \
	else \
	    echo "error: python3 with PyYAML, or nix-shell, is required to run the regen script." >&2; \
	    exit 1; \
	fi
