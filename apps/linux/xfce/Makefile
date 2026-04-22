.PHONY: build install uninstall clean

build:
	@test -d build || meson setup build --buildtype=release
	meson compile -C build

install: build
	meson install -C build

uninstall:
	@[ -d build ] && meson install -C build --dry-run | awk '/Installing/ {print $$NF}' | xargs -r sudo rm -f || true

clean:
	rm -rf build
