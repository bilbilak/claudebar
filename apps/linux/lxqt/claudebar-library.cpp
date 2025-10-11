// SPDX-License-Identifier: GPL-3.0-or-later
#include "claudebar-library.h"
#include "claudebar.h"

ILXQtPanelPlugin *ClaudebarLibrary::instance(
    const ILXQtPanelPluginStartupInfo &startupInfo) const {
    // Make sure translations are available for the very first plugin instance.
    Claudebar::installTranslatorOnce();
    return new Claudebar(startupInfo);
}
