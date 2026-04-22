.PHONY: build install uninstall clean

build:
	@test -d build || cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
	cmake --build build --parallel

install: build
	sudo cmake --install build

clean:
	rm -rf build
