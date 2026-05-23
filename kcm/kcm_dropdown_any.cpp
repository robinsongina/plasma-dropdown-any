// SPDX-License-Identifier: GPL-2.0-or-later
#include "kcm_dropdown_any.h"

#include <KSharedConfig>
#include <KConfigGroup>

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QFile>
#include <QProcess>
#include <QSet>
#include <QTimer>
#include <QVariantMap>

DropdownAnyKCM::DropdownAnyKCM(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    for (int i = 0; i < 10; i++) {
        m_slots.append({QString(), QString(), 100, 50});
    }
    load();

    // Fetch active windows after the event loop starts
    QTimer::singleShot(300, this, &DropdownAnyKCM::fetchActiveWindows);
}

QStringList DropdownAnyKCM::activeWindows() const
{
    return m_activeWindows;
}

QVariantList DropdownAnyKCM::slots() const
{
    QVariantList list;
    for (const auto &s : m_slots) {
        QVariantMap m;
        m[QStringLiteral("windowClass")]   = s.windowClass;
        m[QStringLiteral("shortcut")]      = s.shortcut;
        m[QStringLiteral("widthPercent")]  = s.widthPercent;
        m[QStringLiteral("heightPercent")] = s.heightPercent;
        list << m;
    }
    return list;
}

void DropdownAnyKCM::setSlot(int idx, const QString &windowClass, const QString &shortcut,
                              int widthPct, int heightPct)
{
    if (idx < 0 || idx >= m_slots.size()) return;
    m_slots[idx] = {windowClass, shortcut, widthPct, heightPct};
    setNeedsSave(true);
    Q_EMIT slotsChanged();
}

void DropdownAnyKCM::load()
{
    const auto cfg = KSharedConfig::openConfig(QStringLiteral("kwinrc"))
                         ->group(QStringLiteral("Script-plasma-dropdown-any"));
    for (int i = 0; i < 10; i++) {
        const QString n = QString::number(i + 1);
        m_slots[i].windowClass   = cfg.readEntry(QStringLiteral("windowClass")   + n, QString());
        m_slots[i].shortcut      = cfg.readEntry(QStringLiteral("shortcut")      + n, QString());
        m_slots[i].widthPercent  = cfg.readEntry(QStringLiteral("widthPercent")  + n, 100);
        m_slots[i].heightPercent = cfg.readEntry(QStringLiteral("heightPercent") + n, 50);
    }
    Q_EMIT slotsChanged();
    setNeedsSave(false);
}

void DropdownAnyKCM::save()
{
    auto cfg = KSharedConfig::openConfig(QStringLiteral("kwinrc"))
                   ->group(QStringLiteral("Script-plasma-dropdown-any"));
    for (int i = 0; i < 10; i++) {
        const QString n = QString::number(i + 1);
        cfg.writeEntry(QStringLiteral("windowClass")   + n, m_slots[i].windowClass);
        cfg.writeEntry(QStringLiteral("shortcut")      + n, m_slots[i].shortcut);
        cfg.writeEntry(QStringLiteral("widthPercent")  + n, m_slots[i].widthPercent);
        cfg.writeEntry(QStringLiteral("heightPercent") + n, m_slots[i].heightPercent);
    }
    cfg.sync();
    setNeedsSave(false);

    // Reload the KWin script so new shortcuts get registered immediately
    QDBusInterface scripting(QStringLiteral("org.kde.KWin"),
                             QStringLiteral("/Scripting"),
                             QStringLiteral("org.kde.kwin.Scripting"),
                             QDBusConnection::sessionBus());
    scripting.call(QStringLiteral("unloadScript"), QStringLiteral("plasma-dropdown-any"));
    scripting.call(QStringLiteral("start"));
}

void DropdownAnyKCM::defaults()
{
    for (auto &s : m_slots) s = {QString(), QString(), 100, 50};
    Q_EMIT slotsChanged();
    setNeedsSave(true);
}

void DropdownAnyKCM::fetchActiveWindows()
{
    // Write a temp KWin script that logs window classes via print()
    const QString tmpPath = QStringLiteral("/tmp/kcm_dropdown_list.js");
    QFile f(tmpPath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) return;
    f.write(
        "workspace.windowList().forEach(function(w) {\n"
        "    if (w.resourceClass)\n"
        "        print('KCMWIN:' + w.resourceClass + '|' + (w.caption || ''));\n"
        "});\n"
    );
    f.close();

    QDBusInterface scripting(QStringLiteral("org.kde.KWin"),
                             QStringLiteral("/Scripting"),
                             QStringLiteral("org.kde.kwin.Scripting"),
                             QDBusConnection::sessionBus());
    QDBusReply<int> reply = scripting.call(QStringLiteral("loadScript"),
                                           tmpPath,
                                           QStringLiteral("kcm_list_temp"));
    if (!reply.isValid() || reply.value() < 0) return;

    const QString scriptPath = QStringLiteral("/Scripting/Script%1").arg(reply.value());
    QDBusInterface script(QStringLiteral("org.kde.KWin"), scriptPath,
                          QStringLiteral("org.kde.kwin.Script"),
                          QDBusConnection::sessionBus());
    script.call(QStringLiteral("run"));

    // Parse journalctl after a short delay
    QTimer::singleShot(600, this, [this, tmpPath]() {
        QProcess proc;
        proc.start(QStringLiteral("journalctl"),
                   {QStringLiteral("-t"), QStringLiteral("kwin_wayland"),
                    QStringLiteral("-n"), QStringLiteral("300"),
                    QStringLiteral("--no-pager"),
                    QStringLiteral("--since"), QStringLiteral("5 seconds ago")});
        proc.waitForFinished(3000);

        const QString output = QString::fromLocal8Bit(proc.readAllStandardOutput());
        QStringList windows;
        QSet<QString> seen;

        for (const QString &line : output.split(QLatin1Char('\n'))) {
            const int idx = line.indexOf(QStringLiteral("KCMWIN:"));
            if (idx < 0) continue;
            const QString data = line.mid(idx + 7);
            const int sep = data.indexOf(QLatin1Char('|'));
            const QString cls   = sep >= 0 ? data.left(sep).trimmed()       : data.trimmed();
            const QString title = sep >= 0 ? data.mid(sep + 1).left(60)     : QString();
            if (cls.isEmpty() || seen.contains(cls)) continue;
            seen.insert(cls);
            windows << cls + QStringLiteral(" → ") + title;
        }
        windows.sort();
        QFile::remove(tmpPath);

        if (m_activeWindows != windows) {
            m_activeWindows = windows;
            Q_EMIT activeWindowsChanged();
        }
    });
}

K_PLUGIN_CLASS_WITH_JSON(DropdownAnyKCM, "kcm_dropdown_any.json")

#include "kcm_dropdown_any.moc"
