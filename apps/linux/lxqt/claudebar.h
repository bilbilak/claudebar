// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <ILXQtPanelPlugin.h>
#include <QObject>
#include <QTimer>
#include <QWidget>

class ClaudebarWidget;

class Claudebar : public QObject, public ILXQtPanelPlugin {
    Q_OBJECT
public:
    Claudebar(const ILXQtPanelPluginStartupInfo &startupInfo);
    ~Claudebar() override;

    QWidget *widget() override;
    QString themeId() const override { return QStringLiteral("Claudebar"); }
    Flags flags() const override { return NoFlags; }

    bool isSeparate() const override { return false; }
    bool isExpandable() const override { return false; }

private slots:
    void refresh();

private:
    ClaudebarWidget *m_widget = nullptr;
    QTimer *m_timer = nullptr;
    QString m_helperPath = QStringLiteral("claudebar-helper");
    int m_pollInterval = 300;
};
