// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import org.kde.kwin

pragma ComponentBehavior: Bound

Item {
    id: root

    property var  slotData:     []
    property int  animDuration: 250
    property bool animEnabled:  true

    // ── Config loading ────────────────────────────────────────────────────────

    function loadConfig() {
        var cfg  = []
        var count = parseInt(KWin.readConfig("slotCount", 0), 10)
        var limit = Math.max(count, 20)   // always scan at least 20 slots

        for (var i = 1; i <= limit; i++) {
            var cls = String(KWin.readConfig("windowClass" + i, "")).trim()
            var sc  = String(KWin.readConfig("shortcut"    + i, "")).trim()
            if (!cls || !sc) continue
            cfg.push({
                slotIndex:    i,
                windowClass:  cls,
                shortcutKey:  sc,
                widthPercent: parseInt(KWin.readConfig("widthPercent"  + i, 100), 10) / 100.0,
                heightPercent:parseInt(KWin.readConfig("heightPercent" + i,  50), 10) / 100.0,
                screenTarget: parseInt(KWin.readConfig("screenTarget"  + i,   0), 10),
                windowOpacity:parseInt(KWin.readConfig("opacity"       + i, 100), 10) / 100.0,
                allDesktops:  KWin.readConfig("allDesktops" + i, false) === true ||
                              KWin.readConfig("allDesktops" + i, false) === "true",
                autoHide:     KWin.readConfig("autoHide"    + i, false) === true ||
                              KWin.readConfig("autoHide"    + i, false) === "true",
            })
        }

        root.animEnabled  = KWin.readConfig("animEnabled",  true) !== false &&
                            KWin.readConfig("animEnabled",  true) !== "false"
        root.animDuration = parseInt(KWin.readConfig("animDuration", 250), 10)
        root.slotData     = cfg
        console.log("[DropdownAny] loadConfig —", cfg.length, "slots,",
                    "animDuration:", root.animDuration)
    }

    // ── Slot instances ────────────────────────────────────────────────────────

    Repeater {
        id: slotsRepeater
        model: root.slotData

        DropdownSlot {
            required property var modelData

            slotIndex:    modelData.slotIndex
            windowClass:  modelData.windowClass
            shortcutKey:  modelData.shortcutKey
            widthPercent: modelData.widthPercent
            heightPercent:modelData.heightPercent
            screenTarget: modelData.screenTarget
            windowOpacity:modelData.windowOpacity
            allDesktops:  modelData.allDesktops
            autoHide:     modelData.autoHide
            animDuration: root.animEnabled ? root.animDuration : 0
        }
    }

    // ── Global shortcuts ──────────────────────────────────────────────────────

    ShortcutHandler {
        name:     "DropdownAny-ResizeHeightInc"
        text:     "Dropdown: Increase height"
        sequence: "Alt+Shift+Up"
        onActivated: root.resizeActive(0,  0.05)
    }
    ShortcutHandler {
        name:     "DropdownAny-ResizeHeightDec"
        text:     "Dropdown: Decrease height"
        sequence: "Alt+Shift+Down"
        onActivated: root.resizeActive(0, -0.05)
    }
    ShortcutHandler {
        name:     "DropdownAny-ResizeWidthInc"
        text:     "Dropdown: Increase width"
        sequence: "Alt+Shift+Right"
        onActivated: root.resizeActive( 0.05, 0)
    }
    ShortcutHandler {
        name:     "DropdownAny-ResizeWidthDec"
        text:     "Dropdown: Decrease width"
        sequence: "Alt+Shift+Left"
        onActivated: root.resizeActive(-0.05, 0)
    }

    function resizeActive(dw, dh) {
        var active = Workspace.activeWindow
        if (!active) return
        var lc = active.resourceClass.toLowerCase()
        for (var i = 0; i < slotsRepeater.count; i++) {
            var item = slotsRepeater.itemAt(i)
            if (item && item.windowClass.toLowerCase() === lc) {
                item.resize(dw, dh)
                return
            }
        }
    }

    ShortcutHandler {
        name:     "DropdownAny-ListWindows"
        text:     "Dropdown Any: List active window classes"
        sequence: "Meta+Shift+W"
        onActivated: root.listWindowClasses()
    }

    function listWindowClasses() {
        var wins = Workspace.windows
        var seen = {}
        var lines = []
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i]
            var cls = w.resourceClass
            if (!cls || seen[cls]) continue
            seen[cls] = true
            var title = String(w.caption || "")
            if (title.length > 40) title = title.substring(0, 38) + "…"
            lines.push(cls + " → " + title)
        }
        lines.sort()
        console.log("[DropdownAny] Windows:\n" + lines.join("\n"))
    }

    // ── Live config reload ────────────────────────────────────────────────────
    // Options.configChanged fires when /KWin reconfigure is called — no need
    // for manual disable/enable of the script.

    Connections {
        target: Options
        function onConfigChanged() {
            console.log("[DropdownAny] Config changed — reloading.")
            root.loadConfig()
        }
    }

    // ── Init ──────────────────────────────────────────────────────────────────

    Component.onCompleted: {
        root.loadConfig()
    }
}
