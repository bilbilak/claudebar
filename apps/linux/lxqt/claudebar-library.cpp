// SPDX-License-Identifier: GPL-3.0-or-later
#include "claudebar-library.h"
#include "claudebar.h"

ILXQtPanelPlugin *ClaudebarLibrary::instance(
    const ILXQtPanelPluginStartupInfo &startupInfo) const {
    return new Claudebar(startupInfo);
}
