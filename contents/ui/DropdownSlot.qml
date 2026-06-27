// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import org.kde.kwin

pragma ComponentBehavior: Bound

Item {
    id: slot

    // ── Configuration (set by Repeater delegate) ──────────────────────────────
    required property int    slotIndex
    required property string windowClass
    required property string shortcutKey
    required property real   widthPercent
    required property real   heightPercent
    required property bool   debugMode
    required property int    screenTarget
    required property real   windowOpacity   // 0.0–1.0
    required property bool   allDesktops
    required property bool   autoHide
    required property int    animDuration

    // ── Mutable during live resize ────────────────────────────────────────────
    property real effectiveWidth:  widthPercent
    property real effectiveHeight: heightPercent

    // ── Animation state ───────────────────────────────────────────────────────
    property var  managedWindow:   null
    property real animatedY:       0
    property real animatedOpacity: 0
    property real visibleY:        0
    property real hiddenY:         0

    // ── Sync animated values to the real window ───────────────────────────────

    onAnimatedYChanged: {
        if (!managedWindow) return
        var g = managedWindow.frameGeometry
        managedWindow.frameGeometry = Qt.rect(g.x, animatedY, g.width, g.height)
    }

    onAnimatedOpacityChanged: {
        if (managedWindow) managedWindow.opacity = animatedOpacity
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function resolveScreen() {
        if (slot.screenTarget === 0)
            return Workspace.screenAt(Workspace.cursorPos) || Workspace.activeScreen
        var idx = slot.screenTarget - 1
        return (idx >= 0 && idx < Workspace.screens.length)
               ? Workspace.screens[idx]
               : Workspace.activeScreen
    }

    function computeGeometry() {
        var s = resolveScreen()
        var a = s.geometry
        var w = Math.round(a.width  * slot.effectiveWidth)
        var h = Math.round(a.height * slot.effectiveHeight)
        var x = a.x + Math.round((a.width - w) / 2)
        return Qt.rect(x, a.y, w, h)
    }

    function findWindow() {
        var lc   = slot.windowClass.toLowerCase()
        var wins = Workspace.windows
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i]
            if (w.resourceClass.toLowerCase() === lc ||
                w.resourceName.toLowerCase()  === lc)
                return w
        }
        return null
    }

    function applyWindowFlags(win) {
        win.keepAbove    = true
        win.skipTaskbar  = true
        win.skipPager    = true
        win.skipSwitcher = true
        win.onAllDesktops = slot.allDesktops
        win.noBorder     = true
    }

    // ── Toggle (called by ShortcutHandler) ────────────────────────────────────

    function dbg(msg) {
        console.log("[DropdownAny] " + msg)
        if (!slot.debugMode) return
        callDBus("org.kde.plasmashell", "/org/kde/osdService",
                 "org.kde.osdService", "showText",
                 "utilities-terminal",
                 "[DropdownAny]\n" + msg)
    }

    function toggle() {
        var win = findWindow()
        if (!win) {
            dbg(slot.windowClass + "\nWindow not found")
            return
        }
        slot.managedWindow = win
        var action = (slot.state === "Visible") ? "Hidden" : "Visible"
        dbg(slot.windowClass + "\nAction: " + (action === "Visible" ? "show" : "hide"))
        slot.state = action
    }

    // ── Live resize (called by main.qml's global shortcuts) ───────────────────

    function resize(dw, dh) {
        slot.effectiveWidth  = Math.max(0.10, Math.min(1.0, slot.effectiveWidth  + dw))
        slot.effectiveHeight = Math.max(0.10, Math.min(1.0, slot.effectiveHeight + dh))

        if (slot.managedWindow && slot.state === "Visible") {
            var geo = computeGeometry()
            slot.visibleY = geo.y
            slot.animatedY = geo.y
            slot.managedWindow.frameGeometry = geo
        }

        KWin.writeConfig("widthPercent"  + slot.slotIndex, Math.round(slot.effectiveWidth  * 100))
        KWin.writeConfig("heightPercent" + slot.slotIndex, Math.round(slot.effectiveHeight * 100))

        dbg(slot.windowClass + "\nResize → w:" + Math.round(slot.effectiveWidth * 100) +
            "% h:" + Math.round(slot.effectiveHeight * 100) + "%")
    }

    // ── State machine ─────────────────────────────────────────────────────────

    states: [
        State {
            name: "Visible"

            StateChangeScript {
                name: "before"
                script: {
                    if (!slot.managedWindow) return

                    var geo = slot.computeGeometry()
                    slot.visibleY = geo.y
                    slot.hiddenY  = geo.y - geo.height

                    slot.applyWindowFlags(slot.managedWindow)
                    slot.managedWindow.opacity = 0

                    // Position above screen so slide-in can begin
                    slot.managedWindow.frameGeometry = Qt.rect(geo.x, slot.hiddenY, geo.width, geo.height)
                    slot.animatedY       = slot.hiddenY
                    slot.animatedOpacity = 0

                    // Unminimize and bring to front
                    Workspace.sendClientToScreen(slot.managedWindow, slot.resolveScreen())
                    Workspace.activeWindow = slot.managedWindow
                }
            }

            PropertyChanges {
                target: slot
                animatedY:       slot.visibleY
                animatedOpacity: slot.windowOpacity
            }
        },

        State {
            name: "Hidden"

            StateChangeScript {
                name: "before"
                script: {
                    if (!slot.managedWindow) return

                    // Focus the window just below ours in the stacking order
                    var stack = Workspace.stackingOrder
                    for (var i = stack.indexOf(slot.managedWindow) - 1; i >= 0; --i) {
                        if (!stack[i].minimized) {
                            Workspace.activeWindow = stack[i]
                            break
                        }
                    }
                }
            }

            StateChangeScript {
                name: "after"
                script: {
                    // Minimize after the slide-out completes so KWin won't
                    // fight the animation by re-rendering the window.
                    if (slot.managedWindow) slot.managedWindow.minimized = true
                }
            }

            PropertyChanges {
                target: slot
                animatedY:       slot.hiddenY
                animatedOpacity: 0
            }
        }
    ]

    // ── Transitions ───────────────────────────────────────────────────────────

    transitions: [
        Transition {
            SequentialAnimation {
                ScriptAction { scriptName: "before" }

                ParallelAnimation {
                    NumberAnimation {
                        target:   slot
                        property: "animatedY"
                        duration: slot.animDuration
                        easing.type: Easing.OutExpo
                    }
                    NumberAnimation {
                        target:   slot
                        property: "animatedOpacity"
                        duration: slot.animDuration
                        easing.type: Easing.OutExpo
                    }
                }

                ScriptAction { scriptName: "after" }
            }
        }
    ]

    // ── Per-slot shortcut ─────────────────────────────────────────────────────

    ShortcutHandler {
        name:     "DropdownAny-" + slot.windowClass
        text:     "Dropdown toggle: " + slot.windowClass
        sequence: slot.shortcutKey
        onActivated: slot.toggle()
    }

    // ── Window lifecycle ──────────────────────────────────────────────────────

    Connections {
        target: Workspace

        function onWindowAdded(win) {
            if (win.resourceClass.toLowerCase() !== slot.windowClass.toLowerCase() &&
                win.resourceName.toLowerCase()  !== slot.windowClass.toLowerCase())
                return
            slot.managedWindow = win
            slot.applyWindowFlags(win)
            // New windows start hidden so the first shortcut press reveals them
            var geo = slot.computeGeometry()
            slot.visibleY = geo.y
            slot.hiddenY  = geo.y - geo.height
            win.frameGeometry = Qt.rect(geo.x, slot.hiddenY, geo.width, geo.height)
            win.opacity   = 0
            win.minimized = true
            slot.animatedY       = slot.hiddenY
            slot.animatedOpacity = 0
            slot.state = "Hidden"
        }

        function onWindowRemoved(win) {
            if (win !== slot.managedWindow) return
            slot.managedWindow = null
            slot.state = ""
        }

        function onActiveWindowChanged(win) {
            if (!slot.autoHide)            return
            if (slot.state !== "Visible")  return
            if (!win)                      return
            if (win === slot.managedWindow) return
            slot.state = "Hidden"
        }
    }

    // ── On load: adopt any already-running window ─────────────────────────────

    Component.onCompleted: {
        var win = findWindow()
        if (!win) return
        slot.managedWindow = win
        applyWindowFlags(win)
        // Honour existing position if already on-screen; otherwise park it hidden
        var g = win.frameGeometry
        if (g.y >= 0 && !win.minimized) {
            // Already visible — adopt as "Visible" without animation
            slot.visibleY = g.y
            slot.hiddenY  = g.y - g.height
            slot.animatedY       = g.y
            slot.animatedOpacity = win.opacity
            slot.state = "Visible"
        } else {
            var geo = computeGeometry()
            slot.visibleY = geo.y
            slot.hiddenY  = geo.y - geo.height
            win.frameGeometry = Qt.rect(geo.x, slot.hiddenY, geo.width, geo.height)
            win.opacity   = 0
            win.minimized = true
            slot.animatedY       = slot.hiddenY
            slot.animatedOpacity = 0
            slot.state = "Hidden"
        }
        console.log("[DropdownAny] Adopted existing window for:", slot.windowClass)
    }
}
