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
    Q_PROPERTY(bool debugMode READ debugMode WRITE setDebugMode NOTIFY debugModeChanged)
    Q_PROPERTY(QStringList screenNames   READ screenNames   NOTIFY screenNamesChanged)

public:
    DropdownAnyKCM(QObject *parent, const KPluginMetaData &data);

    QStringList activeWindows() const;
    QVariantList slots() const;
    bool debugMode() const;
    QStringList screenNames() const;

    Q_INVOKABLE void setSlot(int idx,
                             const QString &windowClass,
                             const QString &shortcut,
                             int widthPct,
                             int heightPct,
                             int screenTarget);
    Q_INVOKABLE void addSlot();
    Q_INVOKABLE void addSlotWithClass(const QString &windowClass);
    Q_INVOKABLE void removeSlot(int idx);
    Q_INVOKABLE void fetchActiveWindows();
    void setDebugMode(bool enabled);

    void load()     override;
    void save()     override;
    void defaults() override;

Q_SIGNALS:
    void activeWindowsChanged();
    void slotsChanged();
    void debugModeChanged();
    void screenNamesChanged();

private Q_SLOTS:
    void finalizeWindowCollection();
    void rebuildScreenNames();

private:
    struct SlotData {
        QString windowClass;
        QString shortcut;
        int widthPercent  = 100;
        int heightPercent = 50;
        int screenTarget  = 0;
    };

    QList<SlotData> m_slots;
    QStringList     m_activeWindows;
    QStringList     m_screenNames;
    WindowSink     *m_winSink = nullptr;
    bool            m_debugMode = false;

    QString resolveMainJsPath() const;
};
