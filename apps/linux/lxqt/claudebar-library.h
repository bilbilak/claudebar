// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <ILXQtPanelPlugin.h>

class ClaudebarLibrary : public QObject, public ILXQtPanelPluginLibrary {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "lxqt.org/Panel/PluginInterface/3.0")
    Q_INTERFACES(ILXQtPanelPluginLibrary)
public:
    ILXQtPanelPlugin *instance(const ILXQtPanelPluginStartupInfo &startupInfo) const override;
};
