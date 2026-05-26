// SPDX-License-Identifier: GPL-2.0-or-later
#include "kcm_dropdown_any.h"

#include <KSharedConfig>
#include <KConfigGroup>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QFile>
#include <QGuiApplication>
#include <QScreen>
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
    load();

    rebuildScreenNames();
    connect(qGuiApp, &QGuiApplication::screenAdded,   this, &DropdownAnyKCM::rebuildScreenNames);
    connect(qGuiApp, &QGuiApplication::screenRemoved, this, &DropdownAnyKCM::rebuildScreenNames);

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

QStringList DropdownAnyKCM::screenNames() const
{
    return m_screenNames;
}

void DropdownAnyKCM::rebuildScreenNames()
{
    QStringList names;
    names << QStringLiteral("At cursor screen");
    const auto screens = QGuiApplication::screens();
    for (int i = 0; i < screens.size(); ++i)
        names << QStringLiteral("Screen %1").arg(i + 1);
    if (m_screenNames == names) return;
    m_screenNames = names;
    Q_EMIT screenNamesChanged();
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
        m[QStringLiteral("screenTarget")]  = s.screenTarget;
        list << m;
    }
    return list;
}

void DropdownAnyKCM::setSlot(int idx, const QString &windowClass, const QString &shortcut,
                              int widthPct, int heightPct, int screenTarget)
{
    if (idx < 0 || idx >= m_slots.size()) return;
    qDebug() << "[DropdownAny] KCM setSlot" << idx + 1
             << "| class:" << (windowClass.isEmpty() ? QStringLiteral("(empty)") : windowClass)
             << "| shortcut:" << (shortcut.isEmpty() ? QStringLiteral("(none)") : shortcut)
             << "| size:" << widthPct << "x" << heightPct
             << "| screen:" << screenTarget;
    m_slots[idx] = {windowClass, shortcut, widthPct, heightPct, screenTarget};
    setNeedsSave(true);
    Q_EMIT slotsChanged();
}

void DropdownAnyKCM::addSlot()
{
    m_slots.append({QString(), QString(), 100, 50, 0});
    qDebug() << "[DropdownAny] KCM addSlot → total slots:" << m_slots.size();
    setNeedsSave(true);
    Q_EMIT slotsChanged();
}

void DropdownAnyKCM::addSlotWithClass(const QString &windowClass)
{
    m_slots.append({windowClass.trimmed(), QString(), 100, 50, 0});
    qDebug() << "[DropdownAny] KCM addSlot with class:" << windowClass
             << "→ total slots:" << m_slots.size();
    setNeedsSave(true);
    Q_EMIT slotsChanged();
}

void DropdownAnyKCM::removeSlot(int idx)
{
    if (idx < 0 || idx >= m_slots.size()) return;
    qDebug() << "[DropdownAny] KCM removeSlot" << idx + 1
             << "| class:" << (m_slots[idx].windowClass.isEmpty()
                               ? QStringLiteral("(empty)") : m_slots[idx].windowClass)
             << "→ remaining:" << m_slots.size() - 1;
    m_slots.removeAt(idx);
    setNeedsSave(true);
    Q_EMIT slotsChanged();
}

void DropdownAnyKCM::load()
{
    const auto cfg = KSharedConfig::openConfig(QStringLiteral("kwinrc"))
                         ->group(QStringLiteral("Script-plasma-dropdown-any"));

    m_slots.clear();
    const int storedCount = cfg.readEntry(QStringLiteral("slotCount"), -1);

    if (storedCount >= 0) {
        // New format: read exactly storedCount slots
        for (int i = 0; i < storedCount; i++) {
            const QString n = QString::number(i + 1);
            m_slots.append({
                cfg.readEntry(QStringLiteral("windowClass")   + n, QString()),
                cfg.readEntry(QStringLiteral("shortcut")      + n, QString()),
                cfg.readEntry(QStringLiteral("widthPercent")  + n, 100),
                cfg.readEntry(QStringLiteral("heightPercent") + n, 50),
                cfg.readEntry(QStringLiteral("screenTarget")  + n, 0)
            });
        }
    } else {
        // Old format (no slotCount): scan up to 10, skip blank entries
        for (int i = 0; i < 10; i++) {
            const QString n   = QString::number(i + 1);
            const QString cls = cfg.readEntry(QStringLiteral("windowClass") + n, QString());
            const QString sc  = cfg.readEntry(QStringLiteral("shortcut")    + n, QString());
            if (cls.isEmpty() && sc.isEmpty()) continue;
            m_slots.append({
                cls, sc,
                cfg.readEntry(QStringLiteral("widthPercent")  + n, 100),
                cfg.readEntry(QStringLiteral("heightPercent") + n, 50),
                cfg.readEntry(QStringLiteral("screenTarget")  + n, 0)
            });
        }
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

    // Delete ALL old DropdownAny-* entries from kglobalshortcutsrc, then rewrite
    const int oldCount = oldCfg.readEntry(QStringLiteral("slotCount"), 10);
    for (int i = 0; i < oldCount; i++) {
        const QString oldClass = oldCfg.readEntry(
            QStringLiteral("windowClass") + QString::number(i + 1), QString());
        if (!oldClass.isEmpty())
            kwinGroup.deleteEntry(QStringLiteral("DropdownAny-") + oldClass);
    }

    for (int i = 0; i < m_slots.size(); i++) {
        const QString cls      = m_slots[i].windowClass.trimmed();
        const QString shortcut = m_slots[i].shortcut.trimmed();
        if (cls.isEmpty() || shortcut.isEmpty()) continue;
        kwinGroup.writeEntry(QStringLiteral("DropdownAny-%1").arg(cls),
                             QStringLiteral("%1,none,Dropdown toggle: %2").arg(shortcut, cls));
    }

    globalCfg->sync();

    // Write kwinrc
    auto cfg = KSharedConfig::openConfig(QStringLiteral("kwinrc"))
                   ->group(QStringLiteral("Script-plasma-dropdown-any"));

    cfg.writeEntry(QStringLiteral("slotCount"), (int)m_slots.size());
    for (int i = 0; i < m_slots.size(); i++) {
        const QString n = QString::number(i + 1);
        cfg.writeEntry(QStringLiteral("windowClass")   + n, m_slots[i].windowClass);
        cfg.writeEntry(QStringLiteral("shortcut")      + n, m_slots[i].shortcut);
        cfg.writeEntry(QStringLiteral("widthPercent")  + n, m_slots[i].widthPercent);
        cfg.writeEntry(QStringLiteral("heightPercent") + n, m_slots[i].heightPercent);
        cfg.writeEntry(QStringLiteral("screenTarget")  + n, m_slots[i].screenTarget);
    }
    // Remove stale entries beyond current count
    for (int i = m_slots.size(); i < 20; i++) {
        const QString n = QString::number(i + 1);
        cfg.deleteEntry(QStringLiteral("windowClass")   + n);
        cfg.deleteEntry(QStringLiteral("shortcut")      + n);
        cfg.deleteEntry(QStringLiteral("widthPercent")  + n);
        cfg.deleteEntry(QStringLiteral("heightPercent") + n);
        cfg.deleteEntry(QStringLiteral("screenTarget")  + n);
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
    m_slots.clear();
    m_debugMode = false;
    Q_EMIT slotsChanged();
    Q_EMIT debugModeChanged();
    setNeedsSave(true);
}

void DropdownAnyKCM::fetchActiveWindows()
{
    auto bus = QDBusConnection::sessionBus();
    const QString service = QStringLiteral("local.DropdownAnyKCM.WinList.p%1")
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

    qDebug() << "[DropdownAny] KCM fetchActiveWindows: script loaded, id =" << reply.value()
             << "| service =" << service;

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
    const QString service = QStringLiteral("local.DropdownAnyKCM.WinList.p%1")
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

    qDebug() << "[DropdownAny] KCM finalizeWindowCollection: buffer size ="
             << (m_winSink ? m_winSink->buffer.size() : -1)
             << "| unique windows =" << windows.size()
             << "| list:" << windows;

    if (m_activeWindows != windows) {
        m_activeWindows = windows;
        Q_EMIT activeWindowsChanged();
    } else {
        qDebug() << "[DropdownAny] KCM: activeWindows unchanged, signal NOT emitted";
    }
}

QString DropdownAnyKCM::resolveMainJsPath() const
{
    return QStandardPaths::locate(QStandardPaths::GenericDataLocation,
        QStringLiteral("kwin/scripts/plasma-dropdown-any/contents/code/main.js"));
}

K_PLUGIN_CLASS_WITH_JSON(DropdownAnyKCM, "kcm_dropdown_any.json")

#include "kcm_dropdown_any.moc"
