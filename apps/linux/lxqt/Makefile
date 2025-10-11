.PHONY: build install uninstall clean i18n

REGEN := ../../../scripts/regenerate-translations.py

i18n:
	@if command -v python3 >/dev/null 2>&1; then \
		python3 $(REGEN) lxqt; \
	else \
		nix-shell -p 'python3.withPackages (ps: [ps.pyyaml])' --run 'python3 $(REGEN) lxqt'; \
	fi

build: i18n
	@test -d build || cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
	cmake --build build --parallel

install: build
	sudo cmake --install build

clean:
	rm -rf build
