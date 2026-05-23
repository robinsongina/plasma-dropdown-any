// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <KQuickConfigModule>
#include <KPluginFactory>

#include <QList>
#include <QStringList>
#include <QVariantList>

class WindowSink;

class DropdownAnyKCM : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QStringList activeWindows READ activeWindows NOTIFY activeWindowsChanged)
    Q_PROPERTY(QVariantList slots        READ slots         NOTIFY slotsChanged)

public:
    DropdownAnyKCM(QObject *parent, const KPluginMetaData &data);

    QStringList activeWindows() const;
    QVariantList slots() const;

    Q_INVOKABLE void setSlot(int idx,
                             const QString &windowClass,
                             const QString &shortcut,
                             int widthPct,
                             int heightPct);

    void load()     override;
    void save()     override;
    void defaults() override;

Q_SIGNALS:
    void activeWindowsChanged();
    void slotsChanged();

private Q_SLOTS:
    void finalizeWindowCollection();

private:
    struct SlotData {
        QString windowClass;
        QString shortcut;
        int widthPercent  = 100;
        int heightPercent = 50;
    };

    QList<SlotData> m_slots;
    QStringList     m_activeWindows;
    WindowSink     *m_winSink = nullptr;

    void    fetchActiveWindows();
    QString resolveMainJsPath() const;
};
