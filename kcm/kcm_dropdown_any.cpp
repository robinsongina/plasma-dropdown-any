// SPDX-License-Identifier: GPL-2.0-or-later
#include "kcm_dropdown_any.h"

#include <KSharedConfig>
#include <KConfigGroup>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QFile>
#include <QSet>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantMap>

class WindowSink : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "local.DropdownAnyKCM.WinList")
public:
    explicit WindowSink(QObject *parent = nullptr) : QObject(parent) {}
    QList<QPair<QString, QString>> buffer;
public Q_SLOTS:
    Q_SCRIPTABLE void receiveWindow(const QString &cls, const QString &title)
    {
        buffer.append({cls, title});
    }
};

DropdownAnyKCM::DropdownAnyKCM(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    for (int i = 0; i < 10; i++) {
        m_slots.append({QString(), QString(), 100, 50});
    }
    load();

    QTimer::singleShot(300, this, &DropdownAnyKCM::fetchActiveWindows);
}

QStringList DropdownAnyKCM::activeWindows() const
{
    return m_activeWindows;
}

bool DropdownAnyKCM::debugMode() const
{
    return m_debugMode;
}

void DropdownAnyKCM::setDebugMode(bool enabled)
{
    if (m_debugMode == enabled) return;
    m_debugMode = enabled;
    setNeedsSave(true);
    Q_EMIT debugModeChanged();
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
    m_debugMode = cfg.readEntry(QStringLiteral("debugMode"), false);
    Q_EMIT slotsChanged();
    Q_EMIT debugModeChanged();
    setNeedsSave(false);
}

void DropdownAnyKCM::save()
{
    // Read old config to know which shortcut entries to clean up from kglobalshortcutsrc
    const auto oldCfg = KSharedConfig::openConfig(QStringLiteral("kwinrc"))
                            ->group(QStringLiteral("Script-plasma-dropdown-any"));

    auto globalCfg  = KSharedConfig::openConfig(QStringLiteral("kglobalshortcutsrc"),
                                                 KConfig::NoGlobals);
    auto kwinGroup   = globalCfg->group(QStringLiteral("kwin"));

    for (int i = 0; i < 10; i++) {
        const QString n        = QString::number(i + 1);
        const QString oldClass = oldCfg.readEntry(QStringLiteral("windowClass") + n, QString());
        const QString newClass = m_slots[i].windowClass.trimmed();

        // Remove the old kglobalshortcutsrc entry when the class changes or is cleared
        if (!oldClass.isEmpty() && oldClass != newClass) {
            kwinGroup.deleteEntry(QStringLiteral("DropdownAny-") + oldClass);
        }
        // Also remove if shortcut is being cleared on the same class
        if (!oldClass.isEmpty() && oldClass == newClass && m_slots[i].shortcut.trimmed().isEmpty()) {
            kwinGroup.deleteEntry(QStringLiteral("DropdownAny-") + oldClass);
        }
    }

    // Write new shortcut entries for all non-empty slots
    for (int i = 0; i < 10; i++) {
        const QString cls      = m_slots[i].windowClass.trimmed();
        const QString shortcut = m_slots[i].shortcut.trimmed();
        if (cls.isEmpty() || shortcut.isEmpty()) continue;
        const QString key   = QStringLiteral("DropdownAny-") + cls;
        const QString value = shortcut + QStringLiteral(",none,Dropdown toggle: ") + cls;
        kwinGroup.writeEntry(key, value);
    }

    globalCfg->sync();

    // Write new slot config to kwinrc
    auto cfg = KSharedConfig::openConfig(QStringLiteral("kwinrc"))
                   ->group(QStringLiteral("Script-plasma-dropdown-any"));
    for (int i = 0; i < 10; i++) {
        const QString n = QString::number(i + 1);
        cfg.writeEntry(QStringLiteral("windowClass")   + n, m_slots[i].windowClass);
        cfg.writeEntry(QStringLiteral("shortcut")      + n, m_slots[i].shortcut);
        cfg.writeEntry(QStringLiteral("widthPercent")  + n, m_slots[i].widthPercent);
        cfg.writeEntry(QStringLiteral("heightPercent") + n, m_slots[i].heightPercent);
    }
    cfg.writeEntry(QStringLiteral("debugMode"), m_debugMode);
    cfg.sync();
    setNeedsSave(false);

    // Reload the KWin script so new shortcuts get registered immediately
    const QString mainJsPath = resolveMainJsPath();
    QDBusInterface scripting(QStringLiteral("org.kde.KWin"),
                             QStringLiteral("/Scripting"),
                             QStringLiteral("org.kde.kwin.Scripting"),
                             QDBusConnection::sessionBus());
    scripting.call(QStringLiteral("unloadScript"), QStringLiteral("plasma-dropdown-any"));

    if (mainJsPath.isEmpty()) {
        qWarning() << "[DropdownAny] save: could not locate main.js; live reload skipped";
        return;
    }

    QDBusReply<int> reloadReply = scripting.call(QStringLiteral("loadScript"),
                                                  mainJsPath,
                                                  QStringLiteral("plasma-dropdown-any"));
    if (!reloadReply.isValid() || reloadReply.value() < 0) {
        qWarning() << "[DropdownAny] save: loadScript failed" << reloadReply.error();
        return;
    }

    QDBusInterface mainScript(QStringLiteral("org.kde.KWin"),
                              QStringLiteral("/Scripting/Script%1").arg(reloadReply.value()),
                              QStringLiteral("org.kde.kwin.Script"),
                              QDBusConnection::sessionBus());
    mainScript.call(QStringLiteral("run"));
}

void DropdownAnyKCM::defaults()
{
    for (auto &s : m_slots) s = {QString(), QString(), 100, 50};
    m_debugMode = false;
    Q_EMIT slotsChanged();
    Q_EMIT debugModeChanged();
    setNeedsSave(true);
}

void DropdownAnyKCM::fetchActiveWindows()
{
    auto bus = QDBusConnection::sessionBus();
    const QString service = QStringLiteral("local.DropdownAnyKCM.WinList.%1")
                                .arg(QCoreApplication::applicationPid());

    // Clean up any previous sink
    if (m_winSink) {
        bus.unregisterObject(QStringLiteral("/WinSink"));
        bus.unregisterService(service);
        m_winSink->deleteLater();
        m_winSink = nullptr;
    }

    m_winSink = new WindowSink(this);
    if (!bus.registerService(service)) {
        qWarning() << "[DropdownAny] WinList: registerService failed";
        m_winSink->deleteLater();
        m_winSink = nullptr;
        return;
    }
    if (!bus.registerObject(QStringLiteral("/WinSink"), m_winSink,
                            QDBusConnection::ExportScriptableSlots)) {
        qWarning() << "[DropdownAny] WinList: registerObject failed";
        bus.unregisterService(service);
        m_winSink->deleteLater();
        m_winSink = nullptr;
        return;
    }

    const QString iface = QStringLiteral("local.DropdownAnyKCM.WinList");
    const QString scriptSrc = QStringLiteral(
        "(function() {\n"
        "  var seen = {};\n"
        "  var skip = {plasmashell:1, systemsettings:1, ksmserver:1};\n"
        "  var wins = workspace.windowList();\n"
        "  for (var i = 0; i < wins.length; i++) {\n"
        "    var w = wins[i];\n"
        "    var cls = w.resourceClass || '';\n"
        "    if (!cls || skip[cls] || seen[cls]) continue;\n"
        "    seen[cls] = 1;\n"
        "    callDBus('%1', '/WinSink', '%2', 'receiveWindow',\n"
        "             cls, w.caption || '');\n"
        "  }\n"
        "})();\n"
    ).arg(service, iface);

    const QString tmpPath = QStringLiteral("/tmp/kcm_dropdown_list.js");
    QFile f(tmpPath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[DropdownAny] WinList: could not write temp script";
        return;
    }
    f.write(scriptSrc.toUtf8());
    f.close();

    QDBusInterface scripting(QStringLiteral("org.kde.KWin"),
                             QStringLiteral("/Scripting"),
                             QStringLiteral("org.kde.kwin.Scripting"),
                             bus);
    scripting.call(QStringLiteral("unloadScript"), QStringLiteral("kcm_list_temp"));

    QDBusReply<int> reply = scripting.call(QStringLiteral("loadScript"),
                                           tmpPath,
                                           QStringLiteral("kcm_list_temp"));
    if (!reply.isValid() || reply.value() < 0) {
        qWarning() << "[DropdownAny] WinList: loadScript failed" << reply.error();
        return;
    }

    QDBusInterface script(QStringLiteral("org.kde.KWin"),
                          QStringLiteral("/Scripting/Script%1").arg(reply.value()),
                          QStringLiteral("org.kde.kwin.Script"),
                          bus);
    script.call(QStringLiteral("run"));

    QTimer::singleShot(1500, this, &DropdownAnyKCM::finalizeWindowCollection);
}

void DropdownAnyKCM::finalizeWindowCollection()
{
    auto bus = QDBusConnection::sessionBus();
    const QString service = QStringLiteral("local.DropdownAnyKCM.WinList.%1")
                                .arg(QCoreApplication::applicationPid());

    QDBusInterface scripting(QStringLiteral("org.kde.KWin"),
                             QStringLiteral("/Scripting"),
                             QStringLiteral("org.kde.kwin.Scripting"),
                             bus);
    scripting.call(QStringLiteral("unloadScript"), QStringLiteral("kcm_list_temp"));
    QFile::remove(QStringLiteral("/tmp/kcm_dropdown_list.js"));

    QStringList windows;
    QSet<QString> seen;
    if (m_winSink) {
        for (const auto &pair : std::as_const(m_winSink->buffer)) {
            const QString cls = pair.first.trimmed();
            if (cls.isEmpty() || seen.contains(cls)) continue;
            seen.insert(cls);
            const QString title = pair.second.left(60);
            windows << (title.isEmpty() ? cls : cls + QStringLiteral(" → ") + title);
        }
    }
    windows.sort();

    bus.unregisterObject(QStringLiteral("/WinSink"));
    bus.unregisterService(service);
    if (m_winSink) {
        m_winSink->deleteLater();
        m_winSink = nullptr;
    }

    if (m_activeWindows != windows) {
        m_activeWindows = windows;
        Q_EMIT activeWindowsChanged();
    }
}

QString DropdownAnyKCM::resolveMainJsPath() const
{
    return QStandardPaths::locate(QStandardPaths::GenericDataLocation,
        QStringLiteral("kwin/scripts/plasma-dropdown-any/contents/code/main.js"));
}

K_PLUGIN_CLASS_WITH_JSON(DropdownAnyKCM, "kcm_dropdown_any.json")

#include "kcm_dropdown_any.moc"
