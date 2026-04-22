// SPDX-License-Identifier: GPL-3.0-or-later
#include "claudebar.h"

#include <QAction>
#include <QContextMenuEvent>
#include <QDesktopServices>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMenu>
#include <QPainter>
#include <QPainterPath>
#include <QProcess>
#include <QUrl>
#include <QWidget>

namespace {

constexpr int kBarWidth  = 64;
constexpr int kBarHeight = 6;
constexpr int kBarGap    = 4;

QColor colorFor(double pct, const QString &status, int warn, int crit) {
    if (status != QLatin1String("ok")) return QColor(140, 140, 140);
    if (pct >= crit)                   return QColor(237, 68, 68);
    if (pct >= warn)                   return QColor(245, 158, 63);
    return QColor(66, 186, 96);
}

}  // namespace

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class ClaudebarWidget : public QWidget {
    Q_OBJECT
public:
    double sessionPercent = 0;
    double weeklyPercent  = 0;
    QString status = QStringLiteral("offline");
    int warn = 60;
    int crit = 85;
    QString helperPath = QStringLiteral("claudebar-helper");

    explicit ClaudebarWidget(QWidget *parent = nullptr) : QWidget(parent) {
        setMinimumWidth(kBarWidth + 4);
        setMinimumHeight(kBarHeight * 2 + kBarGap + 6);
        setContextMenuPolicy(Qt::DefaultContextMenu);
    }

signals:
    void refreshRequested();
    void signInRequested();
    void signOutRequested();

protected:
    void paintEvent(QPaintEvent *) override {
        QPainter p(this);
        p.setRenderHint(QPainter::Antialiasing, true);

        const double w = width();
        const double h = height();
        const double totalH = kBarHeight * 2 + kBarGap;
        const double yTop = (h - totalH) / 2.0;
        const double yBot = yTop + kBarHeight + kBarGap;

        drawBar(p, 0, yTop, w, kBarHeight, sessionPercent);
        drawBar(p, 0, yBot, w, kBarHeight, weeklyPercent);
    }

    void contextMenuEvent(QContextMenuEvent *e) override {
        QMenu menu(this);
        menu.addAction(tr("Refresh now"), this, [this]() { emit refreshRequested(); });
        menu.addSeparator();
        menu.addAction(tr("Sign in with Claude…"), this, [this]() { emit signInRequested(); });
        menu.addAction(tr("Sign out"), this, [this]() { emit signOutRequested(); });
        menu.addSeparator();
        menu.addAction(tr("Open claude.ai/settings/usage"), this, []() {
            QDesktopServices::openUrl(QUrl(QStringLiteral("https://claude.ai/settings/usage")));
        });
        menu.exec(e->globalPos());
    }

private:
    void drawBar(QPainter &p, double x, double y, double w, double h, double pct) {
        const double r = h / 2.0;
        QPainterPath track;
        track.addRoundedRect(QRectF(x, y, w, h), r, r);
        p.fillPath(track, QColor(255, 255, 255, 56));

        const double clamped = std::clamp(pct, 0.0, 100.0);
        if (clamped <= 0) return;
        const double fw = std::max(h, w * clamped / 100.0);
        QPainterPath fill;
        fill.addRoundedRect(QRectF(x, y, fw, h), r, r);
        p.fillPath(fill, colorFor(clamped, status, warn, crit));
    }
};

// ---------------------------------------------------------------------------
// Plugin
// ---------------------------------------------------------------------------

Claudebar::Claudebar(const ILXQtPanelPluginStartupInfo &startupInfo)
    : QObject(), ILXQtPanelPlugin(startupInfo) {
    m_widget = new ClaudebarWidget();

    connect(m_widget, &ClaudebarWidget::refreshRequested, this, &Claudebar::refresh);
    connect(m_widget, &ClaudebarWidget::signInRequested, this, [this]() {
        QProcess::startDetached(m_helperPath, { QStringLiteral("signin") });
    });
    connect(m_widget, &ClaudebarWidget::signOutRequested, this, [this]() {
        QProcess::startDetached(m_helperPath, { QStringLiteral("signout") });
        QTimer::singleShot(500, this, &Claudebar::refresh);
    });

    m_timer = new QTimer(this);
    connect(m_timer, &QTimer::timeout, this, &Claudebar::refresh);
    m_timer->start(std::clamp(m_pollInterval, 60, 3600) * 1000);
    QTimer::singleShot(0, this, &Claudebar::refresh);
}

Claudebar::~Claudebar() = default;

QWidget *Claudebar::widget() { return m_widget; }

void Claudebar::refresh() {
    QProcess proc;
    proc.start(m_helperPath, { QStringLiteral("status") });
    if (!proc.waitForFinished(15'000) || proc.exitCode() != 0) {
        m_widget->status = QStringLiteral("offline");
        m_widget->sessionPercent = 0;
        m_widget->weeklyPercent = 0;
        m_widget->update();
        return;
    }
    const auto raw = proc.readAllStandardOutput();
    const auto doc = QJsonDocument::fromJson(raw);
    if (!doc.isObject()) {
        m_widget->status = QStringLiteral("offline");
        m_widget->sessionPercent = 0;
        m_widget->weeklyPercent = 0;
        m_widget->update();
        return;
    }
    const auto obj = doc.object();
    m_widget->status = obj.value(QStringLiteral("status")).toString(QStringLiteral("offline"));
    const auto session = obj.value(QStringLiteral("session")).toObject();
    const auto weekly  = obj.value(QStringLiteral("weekly")).toObject();
    m_widget->sessionPercent = session.value(QStringLiteral("percent")).toDouble(0);
    m_widget->weeklyPercent  = weekly.value(QStringLiteral("percent")).toDouble(0);
    m_widget->update();
}

#include "claudebar.moc"
