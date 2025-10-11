cmake_minimum_required(VERSION 3.16)
project(claudebar-lxqt CXX VERSION 0.0.0)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Define CMAKE_INSTALL_DATADIR / LIBDIR / etc. lxqt-build-tools sets LIBDIR
# but not DATADIR, which left the .desktop / icons / .qm files installing to
# absolute paths from filesystem root (e.g. /lxqt/lxqt-panel/) instead of
# under /usr/share.
include(GNUInstallDirs)

# Detect Qt5 or Qt6 — LXQt 1.x is Qt5-based, LXQt 2.x (Lubuntu 25.04+) is Qt6.
find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Core Gui Widgets LinguistTools)
find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Core Gui Widgets LinguistTools)
find_package(lxqt REQUIRED)
# LXQt 2.x ships its build-tools CMake config under `lxqt2-build-tools`,
# while LXQt 1.x kept the un-versioned `lxqt-build-tools` namespace.
if(QT_VERSION_MAJOR EQUAL 6)
    find_package(lxqt2-build-tools REQUIRED)
else()
    find_package(lxqt-build-tools REQUIRED)
endif()
find_package(PkgConfig REQUIRED)

include(LXQtCompilerSettings)

set(PLUGIN "claudebar")

set(SOURCES
    claudebar.cpp
    claudebar-library.cpp
)
set(HEADERS
    claudebar.h
    claudebar-library.h
)

add_library(${PLUGIN} MODULE ${SOURCES} ${HEADERS})
target_link_libraries(${PLUGIN}
    Qt${QT_VERSION_MAJOR}::Core Qt${QT_VERSION_MAJOR}::Gui Qt${QT_VERSION_MAJOR}::Widgets
    lxqt
)

# PluginSettings::{value,setValue,sync} live in /usr/bin/lxqt-panel itself
# (the panel exports them to plugins via dlopen(RTLD_GLOBAL)). They are not
# in any installed shared library, so the static linker on Ubuntu / GCC 15
# rejects them as undefined object-file references. Tell the linker to
# defer object-file resolution to runtime — matches how in-tree LXQt panel
# plugins are linked.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_link_options(${PLUGIN} PRIVATE LINKER:--unresolved-symbols=ignore-in-object-files)
endif()

install(TARGETS ${PLUGIN}
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/lxqt-panel)

install(FILES ${PLUGIN}.desktop
    DESTINATION ${CMAKE_INSTALL_DATADIR}/lxqt/lxqt-panel)

# Icon — referenced as `Icon=claudebar` in claudebar.desktop. The shared
# source PNGs at multiple panel-relevant sizes live under
# apps/linux/common/icons/<size>x<size>/; install each into the matching
# hicolor bucket so the Qt icon loader resolves them at every panel size.
foreach(SZ 16 22 24 32 48 64 128 256 512)
    install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/../common/icons/${SZ}x${SZ}/claudebar.png
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/${SZ}x${SZ}/apps)
endforeach()

# Translations
#
# .ts files live under translations/ and are generated from i18n/strings.yaml
# by scripts/regenerate-translations.py (see the top-level Makefile or the
# `make i18n` target in this directory). qt5_add_translation() compiles each
# .ts file into a binary .qm at build time. The .qm files are installed to a
# well-known directory that matches the search paths used by
# Claudebar::installTranslatorOnce().
file(GLOB TS_FILES "${CMAKE_CURRENT_SOURCE_DIR}/translations/claudebar_*.ts")
if(TS_FILES)
    if(QT_VERSION_MAJOR EQUAL 6)
        qt6_add_translation(QM_FILES ${TS_FILES})
    else()
        qt5_add_translation(QM_FILES ${TS_FILES})
    endif()
    add_custom_target(${PLUGIN}-translations ALL DEPENDS ${QM_FILES})
    add_dependencies(${PLUGIN} ${PLUGIN}-translations)

    install(FILES ${QM_FILES}
        DESTINATION ${CMAKE_INSTALL_DATADIR}/lxqt/translations)
else()
    message(WARNING
        "No translation files found under translations/. "
        "Run `make i18n` (or `python3 ../../../scripts/regenerate-translations.py lxqt` "
        "from the repo root) to generate them.")
endif()
