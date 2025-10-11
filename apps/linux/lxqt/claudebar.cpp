// SPDX-License-Identifier: GPL-3.0-or-later
#include "claudebar.h"

#include <QAction>
#include <QCheckBox>
#include <QCoreApplication>
#include <QContextMenuEvent>
#include <QDesktopServices>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QFileInfo>
#include <QFont>
#include <QFormLayout>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLabel>
#include <QLocale>
#include <QMenu>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QProcess>
#include <QPushButton>
#include <QSettings>
#include <QSpinBox>
// LXQt 2.x wraps QSettings in a PluginSettings* with the same value/setValue
// API; LXQt 1.x exposed QSettings directly. Use whichever the installed
// headers provide.
#if __has_include(<lxqt/pluginsettings.h>)
#  include <lxqt/pluginsettings.h>
   using ClaudebarSettings = PluginSettings;
#else
   using ClaudebarSettings = QSettings;
#endif
#include <QStandardPaths>
#include <QStringList>
#include <QTranslator>
#include <QUrl>
#include <QVBoxLayout>
#include <QWidget>

namespace {

constexpr int kBarWidth  = 64;
constexpr int kBarHeight = 6;
constexpr int kBarGap    = 4;

// All user-visible strings share the same context as the .ts files generated
// by scripts/regenerate-translations.py, which writes <name>ClaudeBar</name>.
constexpr const char *kTrContext = "ClaudeBar";

inline QString tr_(const char *source) {
    return QCoreApplication::translate(kTrContext, source);
}

// Substitute %d placeholders in printf-style translations (canonical form
// in i18n/strings.yaml) with QString::arg-friendly %1/%2, then collapse
// %% to a literal %.
QString fmtPct1(QString tmpl, int v1) {
    int i = tmpl.indexOf(QStringLiteral("%d"));
    if (i >= 0) tmpl.replace(i, 2, QStringLiteral("%1"));
    return tmpl.arg(v1).replace(QStringLiteral("%%"), QStringLiteral("%"));
}

QString fmtPctTpl(QString tmpl, int v1, int v2) {
    int i = tmpl.indexOf(QStringLiteral("%d"));
    if (i >= 0) {
        tmpl.replace(i, 2, QStringLiteral("%1"));
        i = tmpl.indexOf(QStringLiteral("%d"));
        if (i >= 0) tmpl.replace(i, 2, QStringLiteral("%2"));
    }
    return tmpl.arg(v1).arg(v2).replace(QStringLiteral("%%"), QStringLiteral("%"));
}

QColor colorFor(double pct, const QString &status, int warn, int crit) {
    if (status != QLatin1String("ok")) return QColor(140, 140, 140);
    if (pct >= crit)                   return QColor(237, 68, 68);
    if (pct >= warn)                   return QColor(245, 158, 63);
    return QColor(66, 186, 96);
}

}  // namespace



void Claudebar::installTranslatorOnce() {
    static bool s_installed = false;
    if (s_installed) return;
    s_installed = true;

    if (!qApp) return;

    const QString locale = QLocale::system().name();   // e.g. "fr_FR"
    const QString shortLocale = locale.left(2);        // e.g. "fr"

    const QStringList searchPaths = {
        QStringLiteral("/usr/share/lxqt/translations/"),
        QStringLiteral("/usr/local/share/lxqt/translations/"),
        QDir::homePath() + QStringLiteral("/.local/share/lxqt/translations/"),
    };

    auto *translator = new QTranslator(qApp);
    bool loaded = false;
    for (const QString &dir : searchPaths) {
        if (translator->load(QStringLiteral("claudebar_") + locale, dir)) {
            loaded = true;
            break;
        }
        if (translator->load(QStringLiteral("claudebar_") + shortLocale, dir)) {
            loaded = true;
            break;
        }
    }
    if (loaded) {
        qApp->installTranslator(translator);
    } else {
        delete translator;
    }
}



// Bars-only sub-widget. Extracted so the parent ClaudebarWidget can host it
// alongside optional percentage QLabels in a QHBoxLayout without overlap.
class ClaudebarBars : public QWidget {
    Q_OBJECT
public:
    double sessionPercent = 0;
    double weeklyPercent  = 0;
    QString status = QStringLiteral("offline");
    int warn = 60;
    int crit = 85;

    explicit ClaudebarBars(QWidget *parent = nullptr) : QWidget(parent) {
        setMinimumWidth(kBarWidth);
        setMinimumHeight(kBarHeight * 2 + kBarGap + 6);
        setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Preferred);
    }

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

private:
    // Empty-bar track color sampled from the Qt palette. The previous hardcoded
    // white@22% (rgba 255,255,255,56) was invisible against light panel themes;
    // QPalette::WindowText is the theme-correct foreground for the panel, which
    // we knock down to 18% alpha (~46) for the empty-track look.
    QColor themeTrackColor() const {
        QColor fg = palette().color(QPalette::Active, QPalette::WindowText);
        fg.setAlpha(46);
        return fg;
    }

    void drawBar(QPainter &p, double x, double y, double w, double h, double pct) {
        const double r = h / 2.0;
        QPainterPath track;
        track.addRoundedRect(QRectF(x, y, w, h), r, r);
        p.fillPath(track, themeTrackColor());

        const double clamped = std::clamp(pct, 0.0, 100.0);
        if (clamped <= 0) return;
        const double fw = std::max(h, w * clamped / 100.0);
        QPainterPath fill;
        fill.addRoundedRect(QRectF(x, y, fw, h), r, r);
        p.fillPath(fill, colorFor(clamped, status, warn, crit));
    }
};

class ClaudebarWidget : public QWidget {
    Q_OBJECT
public:
    double sessionPercent = 0;
    double weeklyPercent  = 0;
    QString status = QStringLiteral("offline");
    int warn = 60;
    int crit = 85;
    bool showPercentages = true;

    explicit ClaudebarWidget(QWidget *parent = nullptr) : QWidget(parent) {
        auto *lay = new QHBoxLayout(this);
        lay->setContentsMargins(2, 0, 2, 0);
        lay->setSpacing(4);

        m_bars = new ClaudebarBars(this);
        lay->addWidget(m_bars, 0, Qt::AlignVCenter);

        auto *pctBox = new QVBoxLayout();
        pctBox->setContentsMargins(0, 0, 0, 0);
        pctBox->setSpacing(1);
        m_sessionPct = new QLabel(this);
        m_weeklyPct  = new QLabel(this);
        QFont f = m_sessionPct->font();
        f.setPointSize(8);
        m_sessionPct->setFont(f);
        m_weeklyPct->setFont(f);
        m_sessionPct->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
        m_weeklyPct->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
        m_sessionPct->setMinimumWidth(28);
        m_weeklyPct->setMinimumWidth(28);
        pctBox->addWidget(m_sessionPct);
        pctBox->addWidget(m_weeklyPct);
        lay->addLayout(pctBox);

        setContextMenuPolicy(Qt::DefaultContextMenu);
        applyState();
    }

    // Push all data fields into the bars sub-widget and labels.
    void applyState() {
        m_bars->sessionPercent = sessionPercent;
        m_bars->weeklyPercent  = weeklyPercent;
        m_bars->status         = status;
        m_bars->warn           = warn;
        m_bars->crit           = crit;
        m_bars->update();

        const int s = static_cast<int>(sessionPercent);
        const int w = static_cast<int>(weeklyPercent);
        m_sessionPct->setText(QString::number(s) + QStringLiteral("%"));
        m_weeklyPct->setText(QString::number(w) + QStringLiteral("%"));
        m_sessionPct->setVisible(showPercentages);
        m_weeklyPct->setVisible(showPercentages);

        // Tooltip on the container reaches the bars + labels via Qt's default
        // child-event propagation.
        setToolTip(fmtPctTpl(tr_("ClaudeBar\nSession: %d%%\nWeekly: %d%%"), s, w));
    }

signals:
    void menuRequested(const QPoint &globalPos);

protected:
    void contextMenuEvent(QContextMenuEvent *e) override {
        emit menuRequested(e->globalPos());
    }

    void mousePressEvent(QMouseEvent *e) override {
        if (e->button() == Qt::LeftButton) {
            emit menuRequested(e->globalPosition().toPoint());
            e->accept();
            return;
        }
        QWidget::mousePressEvent(e);
    }

private:
    ClaudebarBars *m_bars = nullptr;
    QLabel *m_sessionPct = nullptr;
    QLabel *m_weeklyPct  = nullptr;
};



class ClaudebarConfigDialog : public QDialog {
    Q_OBJECT
public:
    explicit ClaudebarConfigDialog(ClaudebarSettings *settings, bool signedIn, QWidget *parent = nullptr)
        : QDialog(parent), m_settings(settings) {
        setWindowTitle(tr_("ClaudeBar — Preferences"));

        auto *account = new QGroupBox(tr_("Account"), this);
        auto *accountLay = new QHBoxLayout(account);
        m_signIn = new QPushButton(tr_("Sign in with Claude"), account);
        m_signOut = new QPushButton(tr_("Sign out"), account);
        accountLay->addWidget(m_signIn);
        accountLay->addWidget(m_signOut);
        accountLay->addStretch(1);
        // Show exactly one of Sign in / Sign out for the initial state.
        // setAuthState() is also called from Claudebar::refresh() so the dialog
        // tracks the snapshot if it stays open while the user signs in/out.
        setAuthState(signedIn);
        connect(m_signIn,  &QPushButton::clicked, this, &ClaudebarConfigDialog::signInRequested);
        connect(m_signOut, &QPushButton::clicked, this, &ClaudebarConfigDialog::signOutRequested);

        auto *refresh = new QGroupBox(tr_("Refresh"), this);
        auto *refreshLay = new QFormLayout(refresh);
        m_pollInterval = new QSpinBox(refresh);
        m_pollInterval->setRange(120, 3600);
        m_pollInterval->setSingleStep(30);
        m_pollInterval->setSuffix(QStringLiteral(" s"));
        refreshLay->addRow(tr_("Poll interval (seconds)"), m_pollInterval);

        auto *display = new QGroupBox(tr_("Display"), this);
        auto *displayLay = new QFormLayout(display);
        m_showPercentages = new QCheckBox(tr_("Show numeric percentages next to bars"), display);
        displayLay->addRow(m_showPercentages);
        m_warn = new QSpinBox(display);
        m_warn->setRange(0, 100);
        m_warn->setSingleStep(5);
        m_warn->setSuffix(QStringLiteral(" %"));
        m_crit = new QSpinBox(display);
        m_crit->setRange(0, 100);
        m_crit->setSingleStep(5);
        m_crit->setSuffix(QStringLiteral(" %"));
        displayLay->addRow(tr_("Orange at"), m_warn);
        displayLay->addRow(tr_("Red at"), m_crit);

        auto *buttons = new QDialogButtonBox(
            QDialogButtonBox::Ok | QDialogButtonBox::Cancel | QDialogButtonBox::Apply,
            this);
        connect(buttons, &QDialogButtonBox::accepted, this, [this]() { writeBack(); accept(); });
        connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
        connect(buttons->button(QDialogButtonBox::Apply), &QPushButton::clicked, this, [this]() {
            writeBack();
            emit settingsApplied();
        });

        auto *root = new QVBoxLayout(this);
        root->addWidget(account);
        root->addWidget(refresh);
        root->addWidget(display);
        root->addWidget(buttons);

        loadFromSettings();
    }

signals:
    void signInRequested();
    void signOutRequested();
    void settingsApplied();

public:
    void setAuthState(bool signedIn) {
        if (m_signIn)  m_signIn->setVisible(!signedIn);
        if (m_signOut) m_signOut->setVisible(signedIn);
    }

private:
    void loadFromSettings() {
        m_pollInterval->setValue(m_settings->value(QStringLiteral("poll-interval-seconds"), 300).toInt());
        m_showPercentages->setChecked(m_settings->value(QStringLiteral("show-percentages"), true).toBool());
        m_warn->setValue(m_settings->value(QStringLiteral("warn-threshold"), 60).toInt());
        m_crit->setValue(m_settings->value(QStringLiteral("critical-threshold"), 85).toInt());
    }

    void writeBack() {
        m_settings->setValue(QStringLiteral("poll-interval-seconds"), m_pollInterval->value());
        m_settings->setValue(QStringLiteral("show-percentages"),     m_showPercentages->isChecked());
        m_settings->setValue(QStringLiteral("warn-threshold"),       m_warn->value());
        m_settings->setValue(QStringLiteral("critical-threshold"),   m_crit->value());
        m_settings->sync();
    }

    ClaudebarSettings *m_settings;
    QPushButton *m_signIn = nullptr;
    QPushButton *m_signOut = nullptr;
    QSpinBox          *m_pollInterval = nullptr;
    QCheckBox *m_showPercentages = nullptr;
    QSpinBox  *m_warn = nullptr;
    QSpinBox  *m_crit = nullptr;
};


//
// lxqt-panel inherits its environment from the session, which on Ubuntu /
// Mint usually means $PATH doesn't include $HOME/.local/bin even though
// the user's interactive shell adds it. The top-level `make install-helper`
// installs claudebar-helper there by default, so QProcess::startDetached
// with a bare "claudebar-helper" name fails to find it. Probe the obvious
// fallback locations.
static QString resolveHelperPath() {
    const QByteArray env = qgetenv("CLAUDEBAR_HELPER");
    if (!env.isEmpty()) {
        QFileInfo fi(QString::fromLocal8Bit(env));
        if (fi.isFile() && fi.isExecutable()) return fi.absoluteFilePath();
    }
    const QString pathHit = QStandardPaths::findExecutable(QStringLiteral("claudebar-helper"));
    if (!pathHit.isEmpty()) return pathHit;
    const QStringList candidates = {
        QDir::homePath() + QStringLiteral("/.local/bin/claudebar-helper"),
        QStringLiteral("/usr/local/bin/claudebar-helper"),
        QStringLiteral("/usr/bin/claudebar-helper"),
        QStringLiteral("/usr/libexec/claudebar-helper"),
    };
    for (const QString &c : candidates) {
        QFileInfo fi(c);
        if (fi.isFile() && fi.isExecutable()) return fi.absoluteFilePath();
    }
    return QStringLiteral("claudebar-helper");
}



Claudebar::Claudebar(const ILXQtPanelPluginStartupInfo &startupInfo)
    : QObject(), ILXQtPanelPlugin(startupInfo) {
    // Load translations the first time any plugin instance is constructed.
    installTranslatorOnce();

    m_helperPath = resolveHelperPath();
    m_widget = new ClaudebarWidget();

    loadSettings();
    m_widget->showPercentages = m_showPercentages;
    m_widget->warn            = m_warnThreshold;
    m_widget->crit            = m_critThreshold;
    m_widget->applyState();

    connect(m_widget, &ClaudebarWidget::menuRequested, this, &Claudebar::showDetailsMenu);

    m_timer = new QTimer(this);
    connect(m_timer, &QTimer::timeout, this, &Claudebar::refresh);
    restartPollTimer();
    QTimer::singleShot(0, this, &Claudebar::refresh);
}

Claudebar::~Claudebar() = default;

QWidget *Claudebar::widget() { return m_widget; }

void Claudebar::loadSettings() {
    ClaudebarSettings *s = settings();
    m_pollInterval   = s->value(QStringLiteral("poll-interval-seconds"), 300).toInt();
    m_showPercentages = s->value(QStringLiteral("show-percentages"),     true).toBool();
    m_warnThreshold  = s->value(QStringLiteral("warn-threshold"),        60).toInt();
    m_critThreshold  = s->value(QStringLiteral("critical-threshold"),    85).toInt();
}

void Claudebar::restartPollTimer() {
    if (!m_timer) return;
    m_timer->start(std::clamp(m_pollInterval, 120, 3600) * 1000);
}

void Claudebar::settingsChanged() {
    loadSettings();
    if (m_widget) {
        m_widget->showPercentages = m_showPercentages;
        m_widget->warn            = m_warnThreshold;
        m_widget->crit            = m_critThreshold;
        m_widget->applyState();
    }
    restartPollTimer();
}

QDialog *Claudebar::configureDialog() {
    if (!m_configDialog) {
        const bool signedIn = (m_widget->status != QLatin1String("unauthenticated"));
        m_configDialog = new ClaudebarConfigDialog(settings(), signedIn);
        m_configDialog->setAttribute(Qt::WA_DeleteOnClose, true);
        connect(m_configDialog, &ClaudebarConfigDialog::settingsApplied,
                this, &Claudebar::settingsChanged);
        connect(m_configDialog, &QDialog::accepted,
                this, &Claudebar::settingsChanged);
        connect(m_configDialog, &ClaudebarConfigDialog::signInRequested,
                this, &Claudebar::startSignin);
        connect(m_configDialog, &ClaudebarConfigDialog::signOutRequested,
                this, [this]() {
                    QProcess::startDetached(m_helperPath, { QStringLiteral("signout") });
                    QTimer::singleShot(500, this, &Claudebar::refresh);
                });
    }
    return m_configDialog.data();
}

void Claudebar::showDetailsMenu(const QPoint &globalPos) {
    QMenu menu;

    const int s = static_cast<int>(m_widget->sessionPercent);
    const int w = static_cast<int>(m_widget->weeklyPercent);
    auto *sessionItem = menu.addAction(fmtPct1(tr_("Current session: %d%%"), s));
    sessionItem->setEnabled(false);
    auto *weeklyItem  = menu.addAction(fmtPct1(tr_("Weekly (all models): %d%%"), w));
    weeklyItem->setEnabled(false);

    if (m_widget->status != QLatin1String("ok")) {
        const QString statusText =
            m_widget->status == QLatin1String("offline")        ? tr_("Offline — last value may be stale")
          : m_widget->status == QLatin1String("rate-limited")   ? tr_("Rate limited by Claude API")
          : m_widget->status == QLatin1String("unauthenticated") ? tr_("Not signed in — open Settings to add a token")
                                                                  : QString();
        if (!statusText.isEmpty()) {
            auto *statusItem = menu.addAction(statusText);
            statusItem->setEnabled(false);
        }
    }

    menu.addSeparator();
    menu.addAction(tr_("Refresh now"), this, &Claudebar::refresh);
    menu.addSeparator();
    // Show exactly one of Sign in / Sign out based on current auth state.
    if (m_widget->status == QLatin1String("unauthenticated")) {
        menu.addAction(tr_("Sign in with Claude"), this, [this]() { startSignin(); });
    } else {
        menu.addAction(tr_("Sign out"), this, [this]() {
            QProcess::startDetached(m_helperPath, { QStringLiteral("signout") });
            QTimer::singleShot(500, this, &Claudebar::refresh);
        });
    }
    menu.addSeparator();
    menu.addAction(tr_("Open claude.ai/settings/usage"), this, []() {
        QDesktopServices::openUrl(QUrl(QStringLiteral("https://claude.ai/settings/usage")));
    });
    menu.addSeparator();
    menu.addAction(tr_("Configure…"), this, [this]() {
        QDialog *d = configureDialog();
        if (!d) return;
        d->show();
        d->raise();
        d->activateWindow();
    });

    menu.exec(globalPos);
}

void Claudebar::refresh() {
    QProcess proc;
    proc.start(m_helperPath, { QStringLiteral("status") });
    auto applyOffline = [this]() {
        m_widget->status = QStringLiteral("offline");
        m_widget->sessionPercent = 0;
        m_widget->weeklyPercent = 0;
        m_widget->applyState();
    };
    if (!proc.waitForFinished(15'000) || proc.exitCode() != 0) {
        applyOffline();
        return;
    }
    const auto raw = proc.readAllStandardOutput();
    const auto doc = QJsonDocument::fromJson(raw);
    if (!doc.isObject()) {
        applyOffline();
        return;
    }
    const auto obj = doc.object();
    m_widget->status = obj.value(QStringLiteral("status")).toString(QStringLiteral("offline"));
    const auto session = obj.value(QStringLiteral("session")).toObject();
    const auto weekly  = obj.value(QStringLiteral("weekly")).toObject();
    m_widget->sessionPercent = session.value(QStringLiteral("percent")).toDouble(0);
    m_widget->weeklyPercent  = weekly.value(QStringLiteral("percent")).toDouble(0);
    m_widget->applyState();
    // Keep an open configure dialog's Sign in / Sign out buttons in sync with
    // the live snapshot — useful when the user signs in / out without closing
    // the dialog (or completes OAuth in the browser while it's open).
    if (m_configDialog) {
        const bool signedIn = (m_widget->status != QLatin1String("unauthenticated"));
        m_configDialog->setAuthState(signedIn);
    }
}

// Launch sign-in and poll status until the user finishes the OAuth flow in
// their browser. Without this, the bars stayed on their stale
// `unauthenticated` snapshot until the next regular poll cycle (default 5
// minutes) and users had to manually click Refresh.
void Claudebar::startSignin() {
    QProcess::startDetached(m_helperPath, { QStringLiteral("signin") });
    if (m_signinPollTimer) {
        m_signinPollTimer->stop();
        m_signinPollTimer->deleteLater();
    }
    m_signinPollsRemaining = 20;  // 20 × 3s = 60s
    m_signinPollTimer = new QTimer(this);
    connect(m_signinPollTimer, &QTimer::timeout, this, [this]() {
        if (m_signinPollsRemaining <= 0) {
            m_signinPollTimer->stop();
            m_signinPollTimer->deleteLater();
            m_signinPollTimer = nullptr;
            return;
        }
        m_signinPollsRemaining--;
        refresh();
        if (m_widget->status != QStringLiteral("unauthenticated")) {
            m_signinPollTimer->stop();
            m_signinPollTimer->deleteLater();
            m_signinPollTimer = nullptr;
        }
    });
    m_signinPollTimer->start(3'000);
}

#include "claudebar.moc"
