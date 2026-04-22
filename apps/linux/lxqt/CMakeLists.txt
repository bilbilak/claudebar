cmake_minimum_required(VERSION 3.16)
project(claudebar-lxqt CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt5 REQUIRED COMPONENTS Core Gui Widgets)
find_package(lxqt REQUIRED)
find_package(lxqt-build-tools REQUIRED)
find_package(PkgConfig REQUIRED)

include(LXQtPluginTranslationLoader)
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
    Qt5::Core Qt5::Gui Qt5::Widgets
    lxqt
)

install(TARGETS ${PLUGIN}
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/lxqt-panel)

install(FILES ${PLUGIN}.desktop
    DESTINATION ${CMAKE_INSTALL_DATADIR}/lxqt/lxqt-panel)
