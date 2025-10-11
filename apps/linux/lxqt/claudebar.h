// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <lxqt/ilxqtpanelplugin.h>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QWidget>

class ClaudebarWidget;
class ClaudebarConfigDialog;

class Claudebar : public QObject, public ILXQtPanelPlugin {
    Q_OBJECT
public:
    Claudebar(const ILXQtPanelPluginStartupInfo &startupInfo);
    ~Claudebar() override;

    QWidget *widget() override;
    QString themeId() const override { return QStringLiteral("Claudebar"); }
    Flags flags() const override { return HaveConfigDialog; }
    QDialog *configureDialog() override;
    void settingsChanged() override;

    bool isSeparate() const override { return false; }
    bool isExpandable() const override { return false; }

    // Idempotently loads claudebar_<locale>.qm into the running QApplication.
    // Safe to call from any plugin instance's constructor.
    static void installTranslatorOnce();

private slots:
    void refresh();

private:
    // Launch `claudebar-helper signin` and poll status every 3 s for up to
    // 60 s so the bars update as soon as the browser OAuth flow completes,
    // instead of waiting for the next regular poll tick.
    void startSignin();
    void showDetailsMenu(const QPoint &globalPos);
    void loadSettings();
    void restartPollTimer();

    ClaudebarWidget *m_widget = nullptr;
    QPointer<ClaudebarConfigDialog> m_configDialog;
    QTimer *m_timer = nullptr;
    QTimer *m_signinPollTimer = nullptr;
    int m_signinPollsRemaining = 0;
    QString m_helperPath = QStringLiteral("claudebar-helper");
    int m_pollInterval = 300;
    bool m_showPercentages = true;
    int m_warnThreshold = 60;
    int m_critThreshold = 85;
};
