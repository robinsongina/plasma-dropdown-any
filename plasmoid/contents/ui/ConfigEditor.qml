// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

/**
 * ConfigEditor — full slot-management UI with KCM parity.
 *
 * Data flow:
 *   Component.onCompleted → bridge.run("load") + bridge.run("check-tools")
 *                         + bridge.run("list-windows")
 *   bridge.finished("load")         → populate regularSlotModel/tempSlotModel + debugMode
 *   bridge.finished("check-tools")  → show capability banner if tools absent
 *   bridge.finished("list-windows") → populate windowClassModel
 *   Apply clicked                   → bridge.run("save", json)
 *   bridge.finished("save", 0, …)  → bridge.run("reload-script")
 *   bridge.finished("reload-script") → show result, clear dirty flag
 *
 * Screen names are built from Qt.application.screens (no subprocess),
 * producing the same ordering as the C++ rebuildScreenNames():
 *   index 0 = "At cursor screen"
 *   index 1 = "Screen 1" … index N = "Screen N"
 */
Item {
    id: root

    implicitWidth:  700
    implicitHeight: 600

    // ── models ───────────────────────────────────────────────────────────────
    // Regular and temporary slots are separate models (separate tabs in the
    // UI) even though config-helper.sh persists them as one flat "slots"
    // array — each entry's own temporary flag tells them apart on save/load.
    ListModel { id: regularSlotModel }
    ListModel { id: tempSlotModel }
    ListModel { id: tileModel }
    ListModel { id: windowClassModel }

    // ── state ─────────────────────────────────────────────────────────────────
    property bool debugMode:      false
    property bool dirty:          false
    property bool _saving:        false
    property bool _loadingWindows: false

    // Fixed global shortcuts (not per-slot) — repeat-last and live resize.
    // Defaults mirror what main.js used before these became configurable.
    property string repeatLastShortcut:      "Meta+Shift+R"
    property string resizeHeightIncShortcut: "Alt+Shift+Up"
    property string resizeHeightDecShortcut: "Alt+Shift+Down"
    property string resizeWidthIncShortcut:  "Alt+Shift+Right"
    property string resizeWidthDecShortcut:  "Alt+Shift+Left"
    property string releaseTempSlotShortcut: "Meta+Shift+X"
    property string listShortcutsShortcut:   "Meta+Shift+S"

    // Shared fallback animation for temporary slots — the slide effect can't
    // look up a per-slot style/duration for these (class unknown ahead of
    // time), so all temporary slots share this one instead.
    property string tempSlotAnimationStyle:    "Smooth"
    property int    tempSlotAnimationDuration: 250

    // Screen names built natively from Qt.application.screens
    readonly property var screenNames: {
        var names = [qsTr("At cursor screen")]
        for (var i = 0; i < Qt.application.screens.length; i++) {
            names.push(qsTr("Screen %1").arg(i + 1))
        }
        return names
    }

    // Edge the dropdown slides in from/out to. Index-aligned with directionValues.
    readonly property var directionValues: ["top", "bottom", "left", "right"]
    readonly property var directionLabels: [qsTr("Top"), qsTr("Bottom"), qsTr("Left"), qsTr("Right")]

    // Per-slot animation style, matching effect/contents/code/main.js's
    // CURVE_NAMES exactly (index-aligned isn't required here since the
    // value is stored/sent as the plain name string, not an index).
    readonly property var styleValues: ["Smooth", "Elastic", "Bounce", "Back", "Linear", "Flip3D"]
    readonly property var styleLabels: [qsTr("Smooth"), qsTr("Elastic"), qsTr("Bounce"), qsTr("Back"), qsTr("Linear"), qsTr("Flip 3D")]

    // Tile pair split axis. Index-aligned with orientationValues.
    readonly property var orientationValues: ["horizontal", "vertical"]
    readonly property var orientationLabels: [qsTr("Horizontal (side by side)"), qsTr("Vertical (top/bottom)")]

    // ── subprocess bridge ─────────────────────────────────────────────────────
    ExecBridge {
        id: bridge
        onFinished: function(verb, exitCode, stdout, stderr) {
            _dispatch(verb, exitCode, stdout, stderr)
        }
    }

    // ── lifecycle ─────────────────────────────────────────────────────────────
    Component.onCompleted: {
        bridge.run("load")
        bridge.run("check-tools")
        _loadingWindows = true
        bridge.run("list-windows")
    }

    // ── bridge dispatch ───────────────────────────────────────────────────────
    function _dispatch(verb, exitCode, stdout, stderr) {
        if      (verb === "load")          _onLoad(exitCode, stdout, stderr)
        else if (verb === "list-windows")  _onListWindows(exitCode, stdout, stderr)
        else if (verb === "check-tools")   _onCheckTools(exitCode, stdout)
        else if (verb === "save")          _onSave(exitCode, stderr)
        else if (verb === "reload-script") _onReload(exitCode, stderr)
    }

    function _onLoad(exitCode, stdout, stderr) {
        if (exitCode !== 0) {
            _showStatus(qsTr("Failed to load config: %1").arg(stderr || "unknown error"), true)
            return
        }
        try {
            var data = JSON.parse(stdout)
            debugMode = data.debugMode || false
            repeatLastShortcut      = data.repeatLastShortcut      || "Meta+Shift+R"
            resizeHeightIncShortcut = data.resizeHeightIncShortcut || "Alt+Shift+Up"
            resizeHeightDecShortcut = data.resizeHeightDecShortcut || "Alt+Shift+Down"
            resizeWidthIncShortcut  = data.resizeWidthIncShortcut  || "Alt+Shift+Right"
            resizeWidthDecShortcut  = data.resizeWidthDecShortcut  || "Alt+Shift+Left"
            releaseTempSlotShortcut = data.releaseTempSlotShortcut || "Meta+Shift+X"
            listShortcutsShortcut   = data.listShortcutsShortcut   || "Meta+Shift+S"
            tempSlotAnimationStyle    = data.tempSlotAnimationStyle    || "Smooth"
            tempSlotAnimationDuration = data.tempSlotAnimationDuration !== undefined ? data.tempSlotAnimationDuration : 250
            regularSlotModel.clear()
            tempSlotModel.clear()
            var slots = data.slots || []
            for (var i = 0; i < slots.length; i++) {
                var s = slots[i]
                var isTemp = s.temporary === true
                var entry = {
                    windowClass:   isTemp ? "" : (s.windowClass || ""),
                    shortcut:      s.shortcut      || "",
                    widthPercent:  s.widthPercent  !== undefined ? s.widthPercent  : 100,
                    heightPercent: s.heightPercent !== undefined ? s.heightPercent : 50,
                    screenTarget:  s.screenTarget  !== undefined ? s.screenTarget  : 0,
                    opacity:       s.opacity       !== undefined ? s.opacity       : 100,
                    allDesktops:   s.allDesktops   !== undefined ? s.allDesktops   : false,
                    autoHide:      s.autoHide      !== undefined ? s.autoHide      : false,
                    keepAbove:     s.keepAbove     !== undefined ? s.keepAbove     : true,
                    direction:     s.direction     || "top",
                    animationStyle: s.animationStyle || "Smooth",
                    animationDuration: s.animationDuration !== undefined ? s.animationDuration : 250
                }
                if (isTemp) tempSlotModel.append(entry)
                else regularSlotModel.append(entry)
            }
            tileModel.clear()
            var tiles = data.tiles || []
            for (var j = 0; j < tiles.length; j++) {
                var t = tiles[j]
                tileModel.append({
                    classLeft:     t.classLeft     || "",
                    classRight:    t.classRight    || "",
                    shortcut:      t.shortcut      || "",
                    splitPercent:  t.splitPercent  !== undefined ? t.splitPercent  : 50,
                    widthPercent:  t.widthPercent  !== undefined ? t.widthPercent  : 100,
                    heightPercent: t.heightPercent !== undefined ? t.heightPercent : 100,
                    screenTarget:  t.screenTarget  !== undefined ? t.screenTarget  : 0,
                    opacity:       t.opacity       !== undefined ? t.opacity       : 100,
                    allDesktops:   t.allDesktops   !== undefined ? t.allDesktops   : false,
                    autoHide:      t.autoHide      !== undefined ? t.autoHide      : false,
                    direction:     t.direction     || "top",
                    orientation:   t.orientation   || "horizontal",
                    animationStyle: t.animationStyle || "Smooth",
                    animationDuration: t.animationDuration !== undefined ? t.animationDuration : 250
                })
            }
            dirty = false
        } catch (e) {
            _showStatus(qsTr("Failed to parse config JSON: %1").arg(String(e)), true)
        }
    }

    function _onListWindows(exitCode, stdout, stderr) {
        _loadingWindows = false
        windowClassModel.clear()
        if (exitCode !== 0 || stdout.length === 0) return
        var lines = stdout.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line) continue
            var sep   = line.indexOf(" → ")  // " → "
            var cls   = sep >= 0 ? line.substring(0, sep).trim() : line
            var title = sep >= 0 ? line.substring(sep + 3).trim() : ""
            if (cls) windowClassModel.append({ cls: cls, title: title })
        }
        // Some KWin builds don't route script print() output to the user
        // journal (see config-helper.sh cmd_list_windows comment) — when
        // that happens the helper falls back to an OSD popup + Klipper
        // clipboard round-trip (restoring the previous clipboard contents
        // afterward), and flags it via this stderr marker.
        if (stderr && stderr.indexOf("FALLBACK_CLIPBOARD_OSD") >= 0) {
            _showStatus(
                qsTr("Window list detected via clipboard fallback (your clipboard was used briefly and restored)."),
                false
            )
        }
    }

    function _onCheckTools(exitCode, stdout) {
        if (exitCode !== 0) return  // check-tools always exits 0; non-zero is unexpected
        try {
            var tools   = JSON.parse(stdout)
            var missing = []
            for (var t in tools) {
                if (Object.prototype.hasOwnProperty.call(tools, t) && !tools[t]) {
                    missing.push(t)
                }
            }
            if (missing.length > 0) {
                capabilityBanner.text    = qsTr("Missing tools: %1 — some features may be unavailable.").arg(missing.join(", "))
                capabilityBanner.visible = true
            }
        } catch (e) {
            // Non-critical; ignore JSON parse errors from check-tools
        }
    }

    function _onSave(exitCode, stderr) {
        if (exitCode !== 0) {
            _saving = false
            _showStatus(qsTr("Save failed: %1").arg(stderr || "unknown error"), true)
            return
        }
        // Save succeeded — notify user to manually reload the script AND
        // the slide effect (its per-window animation styles won't update
        // otherwise — confirmed live, /KWin reconfigure alone isn't enough).
        _saving = false
        dirty = false
        _showStatus(
            qsTr("Config saved. To apply: System Settings → KWin Scripts → disable and re-enable \"Dropdown Any Window\", and Desktop Effects → disable and re-enable \"Dropdown Any — Slide\"."),
            false
        )
    }

    function _onReload(exitCode, stderr) {
        // No longer used — kept for compatibility with ExecBridge signal routing
        _saving = false
    }

    function _showStatus(msg, isError) {
        statusMessage.type    = isError ? Kirigami.MessageType.Error
                                        : Kirigami.MessageType.Positive
        statusMessage.text    = msg
        statusMessage.visible = true
    }

    // ── slot helpers ──────────────────────────────────────────────────────────
    function addSlot() {
        regularSlotModel.append({
            windowClass: "", shortcut: "",
            widthPercent: 100, heightPercent: 50,
            screenTarget: 0, opacity: 100,
            allDesktops: false, autoHide: false, keepAbove: true,
            direction: "top", animationStyle: "Smooth", animationDuration: 250
        })
        dirty = true
    }

    function addSlotWithClass(cls) {
        regularSlotModel.append({
            windowClass: cls, shortcut: "",
            widthPercent: 100, heightPercent: 50,
            screenTarget: 0, opacity: 100,
            allDesktops: false, autoHide: false, keepAbove: true,
            direction: "top", animationStyle: "Smooth", animationDuration: 250
        })
        dirty = true
    }

    function removeSlot(idx) {
        regularSlotModel.remove(idx)
        dirty = true
    }

    // ── temp slot helpers ────────────────────────────────────────────────────
    // Temp slot: no class — binds to whatever window is focused the first
    // time its shortcut is triggered, and frees itself when that app closes
    // (or via the global "Release active temp slot" shortcut).
    function addTempSlot() {
        tempSlotModel.append({
            shortcut: "",
            widthPercent: 100, heightPercent: 50,
            screenTarget: 0, opacity: 100,
            allDesktops: false, autoHide: false, keepAbove: true,
            direction: "top", animationStyle: "Smooth", animationDuration: 250
        })
        dirty = true
    }

    function removeTempSlot(idx) {
        tempSlotModel.remove(idx)
        dirty = true
    }

    // Checked in both the Slots and Temporary slots tabs so a duplicate
    // shortcut is caught across both, not just within the same list.
    function isShortcutDuplicated(sc, ownModel, ownIdx) {
        if (!sc) return false
        for (var i = 0; i < regularSlotModel.count; i++) {
            if (ownModel === regularSlotModel && i === ownIdx) continue
            if (regularSlotModel.get(i).shortcut === sc) return true
        }
        for (var j = 0; j < tempSlotModel.count; j++) {
            if (ownModel === tempSlotModel && j === ownIdx) continue
            if (tempSlotModel.get(j).shortcut === sc) return true
        }
        return false
    }

    // ── tile pair helpers ────────────────────────────────────────────────────
    function addTile() {
        tileModel.append({
            classLeft: "", classRight: "", shortcut: "",
            splitPercent: 50, widthPercent: 100, heightPercent: 100,
            screenTarget: 0, opacity: 100,
            allDesktops: false, autoHide: false,
            direction: "top", orientation: "horizontal", animationStyle: "Smooth", animationDuration: 250
        })
        dirty = true
    }

    function removeTile(idx) {
        tileModel.remove(idx)
        dirty = true
    }

    function _buildConfig() {
        var slots = []
        for (var i = 0; i < regularSlotModel.count; i++) {
            var s = regularSlotModel.get(i)
            slots.push({
                windowClass:   s.windowClass,
                shortcut:      s.shortcut,
                widthPercent:  s.widthPercent,
                heightPercent: s.heightPercent,
                screenTarget:  s.screenTarget,
                opacity:       s.opacity,
                allDesktops:   s.allDesktops,
                autoHide:      s.autoHide,
                keepAbove:     s.keepAbove,
                direction:     s.direction,
                animationStyle: s.animationStyle,
                animationDuration: s.animationDuration,
                temporary:     false
            })
        }
        for (var ti = 0; ti < tempSlotModel.count; ti++) {
            var ts = tempSlotModel.get(ti)
            slots.push({
                windowClass:   "",
                shortcut:      ts.shortcut,
                widthPercent:  ts.widthPercent,
                heightPercent: ts.heightPercent,
                screenTarget:  ts.screenTarget,
                opacity:       ts.opacity,
                allDesktops:   ts.allDesktops,
                autoHide:      ts.autoHide,
                keepAbove:     ts.keepAbove,
                direction:     ts.direction,
                animationStyle: ts.animationStyle,
                animationDuration: ts.animationDuration,
                temporary:     true
            })
        }
        var tiles = []
        for (var j = 0; j < tileModel.count; j++) {
            var t = tileModel.get(j)
            tiles.push({
                classLeft:     t.classLeft,
                classRight:    t.classRight,
                shortcut:      t.shortcut,
                splitPercent:  t.splitPercent,
                widthPercent:  t.widthPercent,
                heightPercent: t.heightPercent,
                screenTarget:  t.screenTarget,
                opacity:       t.opacity,
                allDesktops:   t.allDesktops,
                autoHide:      t.autoHide,
                direction:     t.direction,
                orientation:   t.orientation,
                animationStyle: t.animationStyle,
                animationDuration: t.animationDuration
            })
        }
        return JSON.stringify({
            slotCount: slots.length,
            debugMode: debugMode,
            slots:     slots,
            tileCount: tiles.length,
            tiles:     tiles,
            repeatLastShortcut:      repeatLastShortcut,
            resizeHeightIncShortcut: resizeHeightIncShortcut,
            resizeHeightDecShortcut: resizeHeightDecShortcut,
            resizeWidthIncShortcut:  resizeWidthIncShortcut,
            resizeWidthDecShortcut:  resizeWidthDecShortcut,
            releaseTempSlotShortcut: releaseTempSlotShortcut,
            listShortcutsShortcut:   listShortcutsShortcut,
            tempSlotAnimationStyle:    tempSlotAnimationStyle,
            tempSlotAnimationDuration: tempSlotAnimationDuration
        })
    }

    function applyConfig() {
        _saving = true
        statusMessage.visible = false
        bridge.run("save", _buildConfig())
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Controls.ScrollView {
        id: scrollView
        anchors.fill: parent

        ColumnLayout {
            width:   scrollView.availableWidth
            spacing: Kirigami.Units.largeSpacing

            // ── Capability banner ─────────────────────────────────────────────
            Kirigami.InlineMessage {
                id: capabilityBanner
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                type: Kirigami.MessageType.Warning
                showCloseButton: true
                visible: false
            }

            // ── Status message (save/reload result) ───────────────────────────
            Kirigami.InlineMessage {
                id: statusMessage
                Layout.fillWidth: true
                showCloseButton: true
                visible: false
            }

            // ── Active windows ────────────────────────────────────────────────
            Kirigami.Card {
                Layout.fillWidth: true

                header: RowLayout {
                    Kirigami.Heading {
                        level: 3
                        padding: Kirigami.Units.smallSpacing
                        text: qsTr("Active windows")
                        Layout.fillWidth: true
                    }
                    Controls.ToolButton {
                        icon.name: "view-refresh"
                        enabled: !_loadingWindows
                        Controls.ToolTip.text: qsTr("Refresh window list")
                        Controls.ToolTip.visible: hovered
                        Controls.ToolTip.delay: 500
                        onClicked: {
                            _loadingWindows = true
                            bridge.run("list-windows")
                        }
                    }
                }

                contentItem: ColumnLayout {
                    spacing: 0

                    // Column header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Controls.Label {
                            text: qsTr("Window class")
                            font.bold: true
                            Layout.preferredWidth: 200
                        }
                        Controls.Label {
                            text: qsTr("App title")
                            font.bold: true
                            Layout.fillWidth: true
                        }
                    }
                    Kirigami.Separator { Layout.fillWidth: true }

                    // One row per running window
                    Repeater {
                        model: windowClassModel
                        delegate: Column {
                            width: parent.width

                            Controls.ItemDelegate {
                                width: parent.width
                                contentItem: RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Controls.Label {
                                        text: model.cls
                                        font.family: "monospace"
                                        Layout.preferredWidth: 200
                                        elide: Text.ElideRight
                                    }
                                    Controls.Label {
                                        text: model.title
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        color: Kirigami.Theme.disabledTextColor
                                    }
                                }
                                hoverEnabled: true
                                Controls.ToolTip.visible: hovered
                                Controls.ToolTip.delay: 500
                                Controls.ToolTip.text: qsTr("Add \"%1\" as a new dropdown slot").arg(model.cls)
                                onClicked: {
                                    var cls = model.cls
                                    // Fill first empty slot, or create a new one
                                    for (var i = 0; i < regularSlotModel.count; i++) {
                                        if (regularSlotModel.get(i).windowClass === "") {
                                            regularSlotModel.set(i, { windowClass: cls })
                                            dirty = true
                                            return
                                        }
                                    }
                                    addSlotWithClass(cls)
                                }
                            }
                            Kirigami.Separator { width: parent.width }
                        }
                    }

                    // Busy indicator while list-windows is running (~1.2 s)
                    Controls.BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        running: _loadingWindows
                        visible: _loadingWindows
                        padding: Kirigami.Units.largeSpacing
                    }

                    // Empty placeholder
                    Controls.Label {
                        visible: windowClassModel.count === 0 && !_loadingWindows
                        Layout.fillWidth: true
                        text: qsTr("No windows detected yet…")
                        horizontalAlignment: Text.AlignHCenter
                        color: Kirigami.Theme.disabledTextColor
                        padding: Kirigami.Units.largeSpacing
                    }
                }
            }

            // ── Slots / Temporary slots / Tile pairs ────────────────────────────
            Kirigami.Card {
                Layout.fillWidth: true

                header: Controls.TabBar {
                    id: slotsTabBar
                    Controls.TabButton { text: qsTr("Slots") }
                    Controls.TabButton { text: qsTr("Temporary slots") }
                    Controls.TabButton { text: qsTr("Tile pairs") }
                }

                contentItem: StackLayout {
                    currentIndex: slotsTabBar.currentIndex

                    // ── Slots tab ────────────────────────────────────────────
                    ColumnLayout {
                    spacing: 0

                    // Column header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Controls.Label { text: "#";                 font.bold: true; Layout.preferredWidth: 20 }
                        Controls.Label { text: qsTr("Window class"); font.bold: true; Layout.fillWidth: true }
                        Controls.Label { text: qsTr("Shortcut");     font.bold: true; Layout.preferredWidth: 140 }
                        Controls.Label { text: qsTr("Width %");      font.bold: true; Layout.preferredWidth: 75 }
                        Controls.Label { text: qsTr("Height %");     font.bold: true; Layout.preferredWidth: 75 }
                        Item { Layout.preferredWidth: 60 }
                    }
                    Kirigami.Separator { Layout.fillWidth: true }

                    Repeater {
                        model: regularSlotModel
                        delegate: Column {
                            id: slotRow
                            // index is a built-in Repeater property; bind slotIdx so
                            // nested functions always see the current position.
                            property int slotIdx: index
                            // savedClass holds the editable ComboBox text across
                            // model rebuilds (same pattern as kcm/ui/main.qml).
                            property string savedClass: ""
                            // Advanced fields (Screen, Opacity, Slides from, Style,
                            // Duration, All workspaces, Auto-hide) start collapsed —
                            // only App/Shortcut/Width/Height show by default.
                            property bool expanded: false
                            Component.onCompleted: savedClass = model.windowClass

                            width: parent.width

                            // Row 1: primary fields
                            RowLayout {
                                width: parent.width
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    text: index + 1
                                    Layout.preferredWidth: 20
                                }

                                Controls.ComboBox {
                                    id: classCombo
                                    Layout.preferredWidth: 220
                                    editable: true
                                    model: windowClassModel
                                    textRole: "cls"

                                    // Restore savedClass on creation and after model changes;
                                    // do NOT bind editText to avoid Qt internal override.
                                    Component.onCompleted: editText = slotRow.savedClass
                                    Connections {
                                        target: windowClassModel
                                        function onCountChanged() {
                                            classCombo.editText = slotRow.savedClass
                                        }
                                    }

                                    // Two-line dropdown: class (monospace) + dimmed title
                                    delegate: Controls.ItemDelegate {
                                        width: classCombo.popup.width
                                        highlighted: classCombo.highlightedIndex === index
                                        contentItem: ColumnLayout {
                                            spacing: 1
                                            Controls.Label {
                                                text: model.cls
                                                font.family: "monospace"
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                            Controls.Label {
                                                text: model.title
                                                color: Kirigami.Theme.disabledTextColor
                                                Layout.fillWidth: true
                                                visible: model.title !== ""
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    // User picks from dropdown
                                    onActivated: function(comboIdx) {
                                        var cls = windowClassModel.get(comboIdx).cls
                                        slotRow.savedClass = cls
                                        editText = cls
                                        regularSlotModel.set(slotRow.slotIdx, { windowClass: cls })
                                        dirty = true
                                    }

                                    // User types manually → push on focus loss
                                    onActiveFocusChanged: {
                                        if (!activeFocus) {
                                            slotRow.savedClass = editText
                                            regularSlotModel.set(slotRow.slotIdx, { windowClass: editText })
                                            dirty = true
                                        }
                                    }
                                }

                                KQuickControls.KeySequenceItem {
                                    Layout.preferredWidth: 140
                                    keySequence: model.shortcut
                                    checkForConflictsAgainst: 2  // ShortcutTypes.GlobalShortcuts
                                    onKeySequenceModified: {
                                        regularSlotModel.set(slotRow.slotIdx, { shortcut: keySequence.toString() })
                                        dirty = true
                                    }
                                }

                                Controls.SpinBox {
                                    Layout.preferredWidth: 75
                                    from: 10; to: 100; stepSize: 5
                                    value: model.widthPercent
                                    textFromValue: function(v) { return v + " %" }
                                    onValueModified: {
                                        regularSlotModel.set(slotRow.slotIdx, { widthPercent: value })
                                        dirty = true
                                    }
                                }

                                Controls.SpinBox {
                                    Layout.preferredWidth: 75
                                    from: 10; to: 100; stepSize: 5
                                    value: model.heightPercent
                                    textFromValue: function(v) { return v + " %" }
                                    onValueModified: {
                                        regularSlotModel.set(slotRow.slotIdx, { heightPercent: value })
                                        dirty = true
                                    }
                                }

                                Controls.ToolButton {
                                    Layout.preferredWidth: 30
                                    icon.name: slotRow.expanded ? "arrow-up" : "arrow-down"
                                    Controls.ToolTip.text: slotRow.expanded ? qsTr("Hide advanced options") : qsTr("Show advanced options")
                                    Controls.ToolTip.visible: hovered
                                    Controls.ToolTip.delay: 500
                                    onClicked: slotRow.expanded = !slotRow.expanded
                                }

                                Controls.ToolButton {
                                    Layout.preferredWidth: 30
                                    icon.name: "list-remove"
                                    Controls.ToolTip.text: qsTr("Remove this slot")
                                    Controls.ToolTip.visible: hovered
                                    Controls.ToolTip.delay: 500
                                    onClicked: removeSlot(slotRow.slotIdx)
                                }
                            }

                            // Advanced fields — collapsed by default. Flow (not
                            // RowLayout) so groups wrap onto new lines instead
                            // of overflowing when the plasmoid is narrow; each
                            // label+control pair is its own RowLayout so a wrap
                            // never separates a label from its control.
                            Flow {
                                width: parent.width
                                spacing: Kirigami.Units.smallSpacing
                                visible: slotRow.expanded

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Controls.Label { text: qsTr("Screen"); Layout.alignment: Qt.AlignVCenter }
                                    Controls.ComboBox {
                                        Layout.preferredWidth: 120
                                        model: screenNames
                                        currentIndex: regularSlotModel.get(slotRow.slotIdx)
                                                               ? regularSlotModel.get(slotRow.slotIdx).screenTarget || 0
                                                               : 0
                                        onActivated: function(idx) {
                                            regularSlotModel.set(slotRow.slotIdx, { screenTarget: idx })
                                            dirty = true
                                        }
                                    }
                                }

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Controls.Label { text: qsTr("Opacity"); Layout.alignment: Qt.AlignVCenter }
                                    Controls.SpinBox {
                                        Layout.preferredWidth: 90
                                        from: 0; to: 100; stepSize: 5
                                        value: model.opacity
                                        textFromValue: function(v) { return v + " %" }
                                        onValueModified: {
                                            regularSlotModel.set(slotRow.slotIdx, { opacity: value })
                                            dirty = true
                                        }
                                    }
                                }

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Controls.Label { text: qsTr("Slides from"); Layout.alignment: Qt.AlignVCenter }
                                    Controls.ComboBox {
                                        Layout.preferredWidth: 100
                                        model: root.directionLabels
                                        currentIndex: {
                                            var row = regularSlotModel.get(slotRow.slotIdx)
                                            var idx = root.directionValues.indexOf(row ? (row.direction || "top") : "top")
                                            return idx >= 0 ? idx : 0
                                        }
                                        onActivated: function(idx) {
                                            regularSlotModel.set(slotRow.slotIdx, { direction: root.directionValues[idx] })
                                            dirty = true
                                        }
                                    }
                                }

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Controls.Label { text: qsTr("Style"); Layout.alignment: Qt.AlignVCenter }
                                    Controls.ComboBox {
                                        Layout.preferredWidth: 100
                                        model: root.styleLabels
                                        currentIndex: {
                                            var row = regularSlotModel.get(slotRow.slotIdx)
                                            var idx = root.styleValues.indexOf(row ? (row.animationStyle || "Smooth") : "Smooth")
                                            return idx >= 0 ? idx : 0
                                        }
                                        onActivated: function(idx) {
                                            regularSlotModel.set(slotRow.slotIdx, { animationStyle: root.styleValues[idx] })
                                            dirty = true
                                        }
                                    }
                                }

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Controls.Label { text: qsTr("Duration"); Layout.alignment: Qt.AlignVCenter }
                                    Controls.SpinBox {
                                        Layout.preferredWidth: 110
                                        from: 0; to: 9999; stepSize: 10
                                        value: model.animationDuration !== undefined ? model.animationDuration : 250
                                        textFromValue: function(v) { return v + " ms" }
                                        onValueModified: {
                                            regularSlotModel.set(slotRow.slotIdx, { animationDuration: value })
                                            dirty = true
                                        }
                                    }
                                }

                                Controls.CheckBox {
                                    text: qsTr("All workspaces")
                                    checked: model.allDesktops
                                    onToggled: {
                                        regularSlotModel.set(slotRow.slotIdx, { allDesktops: checked })
                                        dirty = true
                                    }
                                }

                                Controls.CheckBox {
                                    text: qsTr("Auto-hide on focus loss")
                                    checked: model.autoHide
                                    onToggled: {
                                        regularSlotModel.set(slotRow.slotIdx, { autoHide: checked })
                                        dirty = true
                                    }
                                }

                                Controls.CheckBox {
                                    text: qsTr("Keep above other windows")
                                    checked: model.keepAbove !== false
                                    Controls.ToolTip.text: qsTr("When focus moves to another app: checked keeps this dropdown floating on top; unchecked lets it fall behind like a normal window. Only matters while it's shown and auto-hide isn't hiding it.")
                                    Controls.ToolTip.visible: hovered
                                    Controls.ToolTip.delay: 500
                                    onToggled: {
                                        regularSlotModel.set(slotRow.slotIdx, { keepAbove: checked })
                                        dirty = true
                                    }
                                }
                            }

                            // Duplicate shortcut warning (checked against both
                            // Slots and Temporary slots — see isShortcutDuplicated)
                            Kirigami.InlineMessage {
                                width: parent.width
                                type: Kirigami.MessageType.Warning
                                text: qsTr("This shortcut is already assigned to another slot.")
                                visible: root.isShortcutDuplicated(model.shortcut, regularSlotModel, slotRow.slotIdx)
                            }

                            Kirigami.Separator { width: parent.width }
                        }
                    }

                    // Empty placeholder
                    Controls.Label {
                        visible: regularSlotModel.count === 0
                        Layout.fillWidth: true
                        text: qsTr("No slots configured yet — click an active window above or use the Add button below.")
                        horizontalAlignment: Text.AlignHCenter
                        color: Kirigami.Theme.disabledTextColor
                        padding: Kirigami.Units.largeSpacing
                        wrapMode: Text.WordWrap
                    }

                    // Add slot button
                    Controls.Button {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        icon.name: "list-add"
                        text: qsTr("Add slot")
                        onClicked: addSlot()
                    }
                    } // end Slots tab

                    // ── Temporary slots tab ─────────────────────────────────────
                    ColumnLayout {
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Controls.Label { text: "#";              font.bold: true; Layout.preferredWidth: 20 }
                        Controls.Label { text: qsTr("App");      font.bold: true; Layout.fillWidth: true }
                        Controls.Label { text: qsTr("Shortcut"); font.bold: true; Layout.preferredWidth: 140 }
                        Controls.Label { text: qsTr("Width %");  font.bold: true; Layout.preferredWidth: 75 }
                        Controls.Label { text: qsTr("Height %"); font.bold: true; Layout.preferredWidth: 75 }
                        Item { Layout.preferredWidth: 60 }
                    }
                    Kirigami.Separator { Layout.fillWidth: true }

                    Repeater {
                        model: tempSlotModel
                        delegate: Column {
                            id: tempSlotRow
                            property int slotIdx: index
                            // Advanced fields start collapsed — only Shortcut/
                            // Width/Height show by default.
                            property bool expanded: false

                            width: parent.width

                            RowLayout {
                                width: parent.width
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    text: index + 1
                                    Layout.preferredWidth: 20
                                }

                                Controls.Label {
                                    Layout.fillWidth: true
                                    text: qsTr("(binds to focused app)")
                                    color: Kirigami.Theme.disabledTextColor
                                    font.italic: true
                                }

                                KQuickControls.KeySequenceItem {
                                    Layout.preferredWidth: 140
                                    keySequence: model.shortcut
                                    checkForConflictsAgainst: 2  // ShortcutTypes.GlobalShortcuts
                                    onKeySequenceModified: {
                                        tempSlotModel.set(tempSlotRow.slotIdx, { shortcut: keySequence.toString() })
                                        dirty = true
                                    }
                                }

                                Controls.SpinBox {
                                    Layout.preferredWidth: 75
                                    from: 10; to: 100; stepSize: 5
                                    value: model.widthPercent
                                    textFromValue: function(v) { return v + " %" }
                                    onValueModified: {
                                        tempSlotModel.set(tempSlotRow.slotIdx, { widthPercent: value })
                                        dirty = true
                                    }
                                }

                                Controls.SpinBox {
                                    Layout.preferredWidth: 75
                                    from: 10; to: 100; stepSize: 5
                                    value: model.heightPercent
                                    textFromValue: function(v) { return v + " %" }
                                    onValueModified: {
                                        tempSlotModel.set(tempSlotRow.slotIdx, { heightPercent: value })
                                        dirty = true
                                    }
                                }

                                Controls.ToolButton {
                                    Layout.preferredWidth: 30
                                    icon.name: tempSlotRow.expanded ? "arrow-up" : "arrow-down"
                                    Controls.ToolTip.text: tempSlotRow.expanded ? qsTr("Hide advanced options") : qsTr("Show advanced options")
                                    Controls.ToolTip.visible: hovered
                                    Controls.ToolTip.delay: 500
                                    onClicked: tempSlotRow.expanded = !tempSlotRow.expanded
                                }

                                Controls.ToolButton {
                                    Layout.preferredWidth: 30
                                    icon.name: "list-remove"
                                    Controls.ToolTip.text: qsTr("Remove this slot")
                                    Controls.ToolTip.visible: hovered
                                    Controls.ToolTip.delay: 500
                                    onClicked: removeTempSlot(tempSlotRow.slotIdx)
                                }
                            }

                            // Advanced fields — collapsed by default (Flow wraps
                            // instead of overflowing on a narrow plasmoid, see
                            // the matching comment in the Slots tab above).
                            Flow {
                                width: parent.width
                                spacing: Kirigami.Units.smallSpacing
                                visible: tempSlotRow.expanded

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Controls.Label { text: qsTr("Screen"); Layout.alignment: Qt.AlignVCenter }
                                    Controls.ComboBox {
                                        Layout.preferredWidth: 120
                                        model: screenNames
                                        currentIndex: tempSlotModel.get(tempSlotRow.slotIdx)
                                                               ? tempSlotModel.get(tempSlotRow.slotIdx).screenTarget || 0
                                                               : 0
                                        onActivated: function(idx) {
                                            tempSlotModel.set(tempSlotRow.slotIdx, { screenTarget: idx })
                                            dirty = true
                                        }
                                    }
                                }

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Controls.Label { text: qsTr("Opacity"); Layout.alignment: Qt.AlignVCenter }
                                    Controls.SpinBox {
                                        Layout.preferredWidth: 90
                                        from: 0; to: 100; stepSize: 5
                                        value: model.opacity
                                        textFromValue: function(v) { return v + " %" }
                                        onValueModified: {
                                            tempSlotModel.set(tempSlotRow.slotIdx, { opacity: value })
                                            dirty = true
                                        }
                                    }
                                }

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Controls.Label { text: qsTr("Slides from"); Layout.alignment: Qt.AlignVCenter }
                                    Controls.ComboBox {
                                        Layout.preferredWidth: 100
                                        model: root.directionLabels
                                        currentIndex: {
                                            var row = tempSlotModel.get(tempSlotRow.slotIdx)
                                            var idx = root.directionValues.indexOf(row ? (row.direction || "top") : "top")
                                            return idx >= 0 ? idx : 0
                                        }
                                        onActivated: function(idx) {
                                            tempSlotModel.set(tempSlotRow.slotIdx, { direction: root.directionValues[idx] })
                                            dirty = true
                                        }
                                    }
                                }

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Controls.Label { text: qsTr("Style"); Layout.alignment: Qt.AlignVCenter }
                                    Controls.ComboBox {
                                        Layout.preferredWidth: 100
                                        model: root.styleLabels
                                        currentIndex: {
                                            var row = tempSlotModel.get(tempSlotRow.slotIdx)
                                            var idx = root.styleValues.indexOf(row ? (row.animationStyle || "Smooth") : "Smooth")
                                            return idx >= 0 ? idx : 0
                                        }
                                        onActivated: function(idx) {
                                            tempSlotModel.set(tempSlotRow.slotIdx, { animationStyle: root.styleValues[idx] })
                                            dirty = true
                                        }
                                    }
                                }

                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Controls.Label { text: qsTr("Duration"); Layout.alignment: Qt.AlignVCenter }
                                    Controls.SpinBox {
                                        Layout.preferredWidth: 110
                                        from: 0; to: 9999; stepSize: 10
                                        value: model.animationDuration !== undefined ? model.animationDuration : 250
                                        textFromValue: function(v) { return v + " ms" }
                                        onValueModified: {
                                            tempSlotModel.set(tempSlotRow.slotIdx, { animationDuration: value })
                                            dirty = true
                                        }
                                    }
                                }

                                Controls.CheckBox {
                                    text: qsTr("All workspaces")
                                    checked: model.allDesktops
                                    onToggled: {
                                        tempSlotModel.set(tempSlotRow.slotIdx, { allDesktops: checked })
                                        dirty = true
                                    }
                                }

                                Controls.CheckBox {
                                    text: qsTr("Auto-hide on focus loss")
                                    checked: model.autoHide
                                    onToggled: {
                                        tempSlotModel.set(tempSlotRow.slotIdx, { autoHide: checked })
                                        dirty = true
                                    }
                                }

                                Controls.CheckBox {
                                    text: qsTr("Keep above other windows")
                                    checked: model.keepAbove !== false
                                    Controls.ToolTip.text: qsTr("When focus moves to another app: checked keeps this dropdown floating on top; unchecked lets it fall behind like a normal window. Only matters while it's shown and auto-hide isn't hiding it.")
                                    Controls.ToolTip.visible: hovered
                                    Controls.ToolTip.delay: 500
                                    onToggled: {
                                        tempSlotModel.set(tempSlotRow.slotIdx, { keepAbove: checked })
                                        dirty = true
                                    }
                                }
                            }

                            Kirigami.InlineMessage {
                                width: parent.width
                                type: Kirigami.MessageType.Warning
                                text: qsTr("This shortcut is already assigned to another slot.")
                                visible: root.isShortcutDuplicated(model.shortcut, tempSlotModel, tempSlotRow.slotIdx)
                            }

                            Kirigami.Separator { width: parent.width }
                        }
                    }

                    Controls.Label {
                        visible: tempSlotModel.count === 0
                        Layout.fillWidth: true
                        text: qsTr("No temporary slots configured yet — click Add temporary slot below.")
                        horizontalAlignment: Text.AlignHCenter
                        color: Kirigami.Theme.disabledTextColor
                        padding: Kirigami.Units.largeSpacing
                        wrapMode: Text.WordWrap
                    }

                    Controls.Button {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        icon.name: "list-add"
                        text: qsTr("Add temporary slot")
                        Controls.ToolTip.text: qsTr("No fixed app — binds to whichever window is focused when its shortcut is first triggered, and frees itself once that app closes.")
                        Controls.ToolTip.visible: hovered
                        Controls.ToolTip.delay: 500
                        onClicked: addTempSlot()
                    }

                    Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }

                    // Shared fallback animation — the slide effect can't look
                    // up a per-slot style/duration for temp slots (class
                    // unknown ahead of time), see
                    // effect/contents/code/main.js header comment.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            text: qsTr("Shared animation style/duration (their app isn't known in advance):")
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Controls.ComboBox {
                            Layout.preferredWidth: 100
                            model: root.styleLabels
                            currentIndex: {
                                var idx = root.styleValues.indexOf(root.tempSlotAnimationStyle)
                                return idx >= 0 ? idx : 0
                            }
                            onActivated: function(idx) {
                                root.tempSlotAnimationStyle = root.styleValues[idx]
                                dirty = true
                            }
                        }

                        Controls.SpinBox {
                            Layout.preferredWidth: 110
                            from: 0; to: 9999; stepSize: 10
                            value: root.tempSlotAnimationDuration
                            textFromValue: function(v) { return v + " ms" }
                            onValueModified: {
                                root.tempSlotAnimationDuration = value
                                dirty = true
                            }
                        }
                    }
                    } // end Temporary slots tab

                    // ── Tile pairs tab ───────────────────────────────────────────
                    ColumnLayout {
                    spacing: 0

                    // Column header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Controls.Label { text: "#";                    font.bold: true; Layout.preferredWidth: 20 }
                        Controls.Label { text: qsTr("Left window");    font.bold: true; Layout.fillWidth: true }
                        Controls.Label { text: qsTr("Right window");   font.bold: true; Layout.fillWidth: true }
                        Controls.Label { text: qsTr("Shortcut");       font.bold: true; Layout.preferredWidth: 140 }
                        Item { Layout.preferredWidth: 30 }
                    }
                    Kirigami.Separator { Layout.fillWidth: true }

                    Repeater {
                        model: tileModel
                        delegate: Column {
                            id: tileRow
                            property int tileIdx: index
                            property string savedClassLeft:  ""
                            property string savedClassRight: ""
                            Component.onCompleted: {
                                savedClassLeft  = model.classLeft
                                savedClassRight = model.classRight
                            }

                            width: parent.width

                            // Row 1: which windows + shortcut
                            RowLayout {
                                width: parent.width
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    text: index + 1
                                    Layout.preferredWidth: 20
                                }

                                Controls.ComboBox {
                                    id: classLeftCombo
                                    Layout.fillWidth: true
                                    editable: true
                                    model: windowClassModel
                                    textRole: "cls"

                                    Component.onCompleted: editText = tileRow.savedClassLeft
                                    Connections {
                                        target: windowClassModel
                                        function onCountChanged() {
                                            classLeftCombo.editText = tileRow.savedClassLeft
                                        }
                                    }

                                    delegate: Controls.ItemDelegate {
                                        width: classLeftCombo.popup.width
                                        highlighted: classLeftCombo.highlightedIndex === index
                                        contentItem: ColumnLayout {
                                            spacing: 1
                                            Controls.Label {
                                                text: model.cls
                                                font.family: "monospace"
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                            Controls.Label {
                                                text: model.title
                                                color: Kirigami.Theme.disabledTextColor
                                                Layout.fillWidth: true
                                                visible: model.title !== ""
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    onActivated: function(comboIdx) {
                                        var cls = windowClassModel.get(comboIdx).cls
                                        tileRow.savedClassLeft = cls
                                        editText = cls
                                        tileModel.set(tileRow.tileIdx, { classLeft: cls })
                                        dirty = true
                                    }

                                    onActiveFocusChanged: {
                                        if (!activeFocus) {
                                            tileRow.savedClassLeft = editText
                                            tileModel.set(tileRow.tileIdx, { classLeft: editText })
                                            dirty = true
                                        }
                                    }
                                }

                                Controls.ComboBox {
                                    id: classRightCombo
                                    Layout.fillWidth: true
                                    editable: true
                                    model: windowClassModel
                                    textRole: "cls"

                                    Component.onCompleted: editText = tileRow.savedClassRight
                                    Connections {
                                        target: windowClassModel
                                        function onCountChanged() {
                                            classRightCombo.editText = tileRow.savedClassRight
                                        }
                                    }

                                    delegate: Controls.ItemDelegate {
                                        width: classRightCombo.popup.width
                                        highlighted: classRightCombo.highlightedIndex === index
                                        contentItem: ColumnLayout {
                                            spacing: 1
                                            Controls.Label {
                                                text: model.cls
                                                font.family: "monospace"
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                            Controls.Label {
                                                text: model.title
                                                color: Kirigami.Theme.disabledTextColor
                                                Layout.fillWidth: true
                                                visible: model.title !== ""
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    onActivated: function(comboIdx) {
                                        var cls = windowClassModel.get(comboIdx).cls
                                        tileRow.savedClassRight = cls
                                        editText = cls
                                        tileModel.set(tileRow.tileIdx, { classRight: cls })
                                        dirty = true
                                    }

                                    onActiveFocusChanged: {
                                        if (!activeFocus) {
                                            tileRow.savedClassRight = editText
                                            tileModel.set(tileRow.tileIdx, { classRight: editText })
                                            dirty = true
                                        }
                                    }
                                }

                                KQuickControls.KeySequenceItem {
                                    Layout.preferredWidth: 140
                                    keySequence: model.shortcut
                                    checkForConflictsAgainst: 2  // ShortcutTypes.GlobalShortcuts
                                    onKeySequenceModified: {
                                        tileModel.set(tileRow.tileIdx, { shortcut: keySequence.toString() })
                                        dirty = true
                                    }
                                }

                                Controls.ToolButton {
                                    Layout.preferredWidth: 30
                                    icon.name: "list-remove"
                                    Controls.ToolTip.text: qsTr("Remove this tile pair")
                                    Controls.ToolTip.visible: hovered
                                    Controls.ToolTip.delay: 500
                                    onClicked: removeTile(tileRow.tileIdx)
                                }
                            }

                            // Row 2: geometry fields
                            RowLayout {
                                width: parent.width
                                spacing: Kirigami.Units.smallSpacing

                                Item { Layout.preferredWidth: 20 }

                                Controls.Label {
                                    text: qsTr("Split")
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Controls.SpinBox {
                                    Layout.preferredWidth: 90
                                    from: 10; to: 90; stepSize: 5
                                    value: model.splitPercent
                                    textFromValue: function(v) { return v + " % / " + (100 - v) + " %" }
                                    onValueModified: {
                                        tileModel.set(tileRow.tileIdx, { splitPercent: value })
                                        dirty = true
                                    }
                                }

                                Controls.Label {
                                    text: qsTr("Width")
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Controls.SpinBox {
                                    Layout.preferredWidth: 75
                                    from: 10; to: 100; stepSize: 5
                                    value: model.widthPercent
                                    textFromValue: function(v) { return v + " %" }
                                    onValueModified: {
                                        tileModel.set(tileRow.tileIdx, { widthPercent: value })
                                        dirty = true
                                    }
                                }

                                Controls.Label {
                                    text: qsTr("Height")
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Controls.SpinBox {
                                    Layout.preferredWidth: 75
                                    from: 10; to: 100; stepSize: 5
                                    value: model.heightPercent
                                    textFromValue: function(v) { return v + " %" }
                                    onValueModified: {
                                        tileModel.set(tileRow.tileIdx, { heightPercent: value })
                                        dirty = true
                                    }
                                }

                                Controls.ComboBox {
                                    Layout.preferredWidth: 120
                                    model: screenNames
                                    currentIndex: tileModel.get(tileRow.tileIdx)
                                                           ? tileModel.get(tileRow.tileIdx).screenTarget || 0
                                                           : 0
                                    onActivated: function(idx) {
                                        tileModel.set(tileRow.tileIdx, { screenTarget: idx })
                                        dirty = true
                                    }
                                }

                                Controls.ComboBox {
                                    Layout.preferredWidth: 100
                                    model: root.directionLabels
                                    currentIndex: {
                                        var row = tileModel.get(tileRow.tileIdx)
                                        var idx = root.directionValues.indexOf(row ? (row.direction || "top") : "top")
                                        return idx >= 0 ? idx : 0
                                    }
                                    onActivated: function(idx) {
                                        tileModel.set(tileRow.tileIdx, { direction: root.directionValues[idx] })
                                        dirty = true
                                    }
                                }

                                Controls.ComboBox {
                                    Layout.preferredWidth: 190
                                    model: root.orientationLabels
                                    currentIndex: {
                                        var row = tileModel.get(tileRow.tileIdx)
                                        var idx = root.orientationValues.indexOf(row ? (row.orientation || "horizontal") : "horizontal")
                                        return idx >= 0 ? idx : 0
                                    }
                                    onActivated: function(idx) {
                                        tileModel.set(tileRow.tileIdx, { orientation: root.orientationValues[idx] })
                                        dirty = true
                                    }
                                }

                                Controls.ComboBox {
                                    Layout.preferredWidth: 100
                                    model: root.styleLabels
                                    currentIndex: {
                                        var row = tileModel.get(tileRow.tileIdx)
                                        var idx = root.styleValues.indexOf(row ? (row.animationStyle || "Smooth") : "Smooth")
                                        return idx >= 0 ? idx : 0
                                    }
                                    onActivated: function(idx) {
                                        tileModel.set(tileRow.tileIdx, { animationStyle: root.styleValues[idx] })
                                        dirty = true
                                    }
                                }

                                Controls.SpinBox {
                                    Layout.preferredWidth: 110
                                    from: 0; to: 9999; stepSize: 10
                                    value: model.animationDuration !== undefined ? model.animationDuration : 250
                                    textFromValue: function(v) { return v + " ms" }
                                    onValueModified: {
                                        tileModel.set(tileRow.tileIdx, { animationDuration: value })
                                        dirty = true
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }

                            // Row 3: opacity + toggles
                            RowLayout {
                                width: parent.width
                                spacing: Kirigami.Units.smallSpacing

                                Item { Layout.preferredWidth: 20 }

                                Controls.Label {
                                    text: qsTr("Opacity")
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Controls.SpinBox {
                                    Layout.preferredWidth: 90
                                    from: 0; to: 100; stepSize: 5
                                    value: model.opacity
                                    textFromValue: function(v) { return v + " %" }
                                    onValueModified: {
                                        tileModel.set(tileRow.tileIdx, { opacity: value })
                                        dirty = true
                                    }
                                }

                                Controls.CheckBox {
                                    text: qsTr("All workspaces")
                                    checked: model.allDesktops
                                    onToggled: {
                                        tileModel.set(tileRow.tileIdx, { allDesktops: checked })
                                        dirty = true
                                    }
                                }

                                Controls.CheckBox {
                                    text: qsTr("Auto-hide on focus loss")
                                    checked: model.autoHide
                                    onToggled: {
                                        tileModel.set(tileRow.tileIdx, { autoHide: checked })
                                        dirty = true
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }

                            Kirigami.Separator { width: parent.width }
                        }
                    }

                    // Empty placeholder
                    Controls.Label {
                        visible: tileModel.count === 0
                        Layout.fillWidth: true
                        text: qsTr("No tile pairs configured — click Add tile pair to show two apps side by side.")
                        horizontalAlignment: Text.AlignHCenter
                        color: Kirigami.Theme.disabledTextColor
                        padding: Kirigami.Units.largeSpacing
                        wrapMode: Text.WordWrap
                    }

                    // Add tile button
                    Controls.Button {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        icon.name: "list-add"
                        text: qsTr("Add tile pair")
                        onClicked: addTile()
                    }
                    } // end Tile pairs tab
                }
            }

            // ── Hint ─────────────────────────────────────────────────────────
            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                text: qsTr("After saving, the KWin script is reloaded automatically.\nShortcut format: F12 · Meta+F1 · Ctrl+F12")
            }

            // ── Global shortcuts ────────────────────────────────────────────────
            // Fixed, single-instance shortcuts (not per-slot) — repeat the last
            // activated slot/tile, and live-resize the currently focused dropdown.
            Kirigami.Card {
                Layout.fillWidth: true

                header: Kirigami.Heading {
                    level: 3
                    padding: Kirigami.Units.smallSpacing
                    text: qsTr("Global shortcuts")
                }

                contentItem: GridLayout {
                    columns: 2
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: [
                            { label: qsTr("Repeat last activated slot/tile"), prop: "repeatLastShortcut" },
                            { label: qsTr("Increase height"),                 prop: "resizeHeightIncShortcut" },
                            { label: qsTr("Decrease height"),                 prop: "resizeHeightDecShortcut" },
                            { label: qsTr("Increase width"),                  prop: "resizeWidthIncShortcut" },
                            { label: qsTr("Decrease width"),                  prop: "resizeWidthDecShortcut" },
                            { label: qsTr("Release active temp slot"),        prop: "releaseTempSlotShortcut" },
                            { label: qsTr("List slots/tiles + shortcuts"),    prop: "listShortcutsShortcut" }
                        ]
                        delegate: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: modelData.label
                                Layout.preferredWidth: 190
                            }

                            KQuickControls.KeySequenceItem {
                                Layout.preferredWidth: 130
                                keySequence: root[modelData.prop]
                                checkForConflictsAgainst: 2  // ShortcutTypes.GlobalShortcuts
                                onKeySequenceModified: {
                                    root[modelData.prop] = keySequence.toString()
                                    dirty = true
                                }
                            }
                        }
                    }
                }
            }

            // ── Developer options ─────────────────────────────────────────────
            Kirigami.Card {
                Layout.fillWidth: true

                header: Kirigami.Heading {
                    level: 3
                    padding: Kirigami.Units.smallSpacing
                    text: qsTr("Developer options")
                }

                contentItem: Controls.CheckBox {
                    text: qsTr("Enable debug mode — shows an OSD notification on every shortcut trigger with the window class, action taken, and any errors")
                    checked: root.debugMode
                    onToggled: {
                        root.debugMode = checked
                        dirty = true
                    }
                }
            }

            // ── Apply button row ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Kirigami.Units.largeSpacing

                Item { Layout.fillWidth: true }

                Controls.BusyIndicator {
                    visible: _saving
                    running: _saving
                    Layout.preferredWidth:  Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }

                Controls.Button {
                    text: qsTr("Apply")
                    icon.name: "dialog-ok-apply"
                    enabled: dirty && !_saving
                    onClicked: applyConfig()
                }
            }
        }
    }
}
