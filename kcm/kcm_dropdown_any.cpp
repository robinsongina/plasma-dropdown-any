// SPDX-License-Identifier: GPL-2.0-or-later
#include "kcm_dropdown_any.h"

#include <KSharedConfig>
#include <KConfigGroup>

#include <KWayland/Client/connection_thread.h>
#include <KWayland/Client/registry.h>
#include <KWayland/Client/plasmawindowmanagement.h>

#include <QSet>
#include <QTimer>
#include <QVariantMap>

DropdownAnyKCM::DropdownAnyKCM(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    for (int i = 0; i < 10; i++) {
        m_slots.append({QString(), QString(), 100, 50});
    }
    initWaylandWindowList();
    load();
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
}

void DropdownAnyKCM::defaults()
{
    for (auto &s : m_slots) s = {QString(), QString(), 100, 50};
    Q_EMIT slotsChanged();
    setNeedsSave(true);
}

void DropdownAnyKCM::initWaylandWindowList()
{
    auto *conn = KWayland::Client::ConnectionThread::fromApplication(this);
    if (!conn) return;

    auto *reg = new KWayland::Client::Registry(this);
    reg->create(conn);

    connect(reg, &KWayland::Client::Registry::plasmaWindowManagementAnnounced,
            this, [this, reg](quint32 name, quint32 version) {
        auto *pwm = reg->createPlasmaWindowManagement(name, version, this);
        connect(pwm, &KWayland::Client::PlasmaWindowManagement::windowCreated,
                this, [this, pwm]() { refreshWindows(pwm); });
        QTimer::singleShot(400, this, [this, pwm]() { refreshWindows(pwm); });
    });

    reg->setup();
    conn->roundtrip();
}

void DropdownAnyKCM::refreshWindows(KWayland::Client::PlasmaWindowManagement *pwm)
{
    QStringList windows;
    QSet<QString> seen;
    for (auto *w : pwm->windows()) {
        const QString id = w->appId();
        if (id.isEmpty() || seen.contains(id)) continue;
        seen.insert(id);
        const QString title = w->title().left(60);
        windows << id + QStringLiteral(" → ") + title;
    }
    windows.sort();
    if (m_activeWindows != windows) {
        m_activeWindows = windows;
        Q_EMIT activeWindowsChanged();
    }
}

K_PLUGIN_CLASS_WITH_JSON(DropdownAnyKCM, "kcm_dropdown_any.json")

#include "kcm_dropdown_any.moc"
