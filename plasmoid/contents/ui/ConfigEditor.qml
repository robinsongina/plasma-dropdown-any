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
 *   bridge.finished("load")         → populate slotModel + debugMode
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
    ListModel { id: slotModel }
    ListModel { id: windowClassModel }

    // ── state ─────────────────────────────────────────────────────────────────
    property bool debugMode:      false
    property bool dirty:          false
    property bool _saving:        false
    property bool _loadingWindows: false

    // Screen names built natively from Qt.application.screens
    readonly property var screenNames: {
        var names = [qsTr("At cursor screen")]
        for (var i = 0; i < Qt.application.screens.length; i++) {
            names.push(qsTr("Screen %1").arg(i + 1))
        }
        return names
    }

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
        else if (verb === "list-windows")  _onListWindows(exitCode, stdout)
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
            slotModel.clear()
            var slots = data.slots || []
            for (var i = 0; i < slots.length; i++) {
                var s = slots[i]
                slotModel.append({
                    windowClass:   s.windowClass   || "",
                    shortcut:      s.shortcut      || "",
                    widthPercent:  s.widthPercent  !== undefined ? s.widthPercent  : 100,
                    heightPercent: s.heightPercent !== undefined ? s.heightPercent : 50,
                    screenTarget:  s.screenTarget  !== undefined ? s.screenTarget  : 0,
                    opacity:       s.opacity       !== undefined ? s.opacity       : 100,
                    allDesktops:   s.allDesktops   !== undefined ? s.allDesktops   : false,
                    autoHide:      s.autoHide      !== undefined ? s.autoHide      : false
                })
            }
            dirty = false
        } catch (e) {
            _showStatus(qsTr("Failed to parse config JSON: %1").arg(String(e)), true)
        }
    }

    function _onListWindows(exitCode, stdout) {
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
        // Save succeeded — chain the reload step
        bridge.run("reload-script")
    }

    function _onReload(exitCode, stderr) {
        _saving = false
        if (exitCode !== 0) {
            _showStatus(
                qsTr("Config saved but script reload failed: %1").arg(stderr || "unknown error"),
                true
            )
        } else {
            dirty = false
            _showStatus(qsTr("Configuration saved and script reloaded."), false)
        }
    }

    function _showStatus(msg, isError) {
        statusMessage.type    = isError ? Kirigami.MessageType.Error
                                        : Kirigami.MessageType.Positive
        statusMessage.text    = msg
        statusMessage.visible = true
    }

    // ── slot helpers ──────────────────────────────────────────────────────────
    function addSlot() {
        slotModel.append({
            windowClass: "", shortcut: "",
            widthPercent: 100, heightPercent: 50,
            screenTarget: 0, opacity: 100,
            allDesktops: false, autoHide: false
        })
        dirty = true
    }

    function addSlotWithClass(cls) {
        slotModel.append({
            windowClass: cls, shortcut: "",
            widthPercent: 100, heightPercent: 50,
            screenTarget: 0, opacity: 100,
            allDesktops: false, autoHide: false
        })
        dirty = true
    }

    function removeSlot(idx) {
        slotModel.remove(idx)
        dirty = true
    }

    function _buildConfig() {
        var slots = []
        for (var i = 0; i < slotModel.count; i++) {
            var s = slotModel.get(i)
            slots.push({
                windowClass:   s.windowClass,
                shortcut:      s.shortcut,
                widthPercent:  s.widthPercent,
                heightPercent: s.heightPercent,
                screenTarget:  s.screenTarget,
                opacity:       s.opacity,
                allDesktops:   s.allDesktops,
                autoHide:      s.autoHide
            })
        }
        return JSON.stringify({
            slotCount: slots.length,
            debugMode: debugMode,
            slots:     slots
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
                                    for (var i = 0; i < slotModel.count; i++) {
                                        if (slotModel.get(i).windowClass === "") {
                                            slotModel.set(i, { windowClass: cls })
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

            // ── Registered slots ──────────────────────────────────────────────
            Kirigami.Card {
                Layout.fillWidth: true

                header: Kirigami.Heading {
                    level: 3
                    padding: Kirigami.Units.smallSpacing
                    text: qsTr("Registered dropdown slots")
                }

                contentItem: ColumnLayout {
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
                        Controls.Label { text: qsTr("Screen");       font.bold: true; Layout.preferredWidth: 120 }
                        Item { Layout.preferredWidth: 30 }
                    }
                    Kirigami.Separator { Layout.fillWidth: true }

                    Repeater {
                        model: slotModel
                        delegate: Column {
                            id: slotRow
                            // index is a built-in Repeater property; bind slotIdx so
                            // nested functions always see the current position.
                            property int slotIdx: index
                            // savedClass holds the editable ComboBox text across
                            // model rebuilds (same pattern as kcm/ui/main.qml).
                            property string savedClass: ""
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
                                    Layout.fillWidth: true
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
                                        slotModel.set(slotRow.slotIdx, { windowClass: cls })
                                        dirty = true
                                    }

                                    // User types manually → push on focus loss
                                    onActiveFocusChanged: {
                                        if (!activeFocus) {
                                            slotRow.savedClass = editText
                                            slotModel.set(slotRow.slotIdx, { windowClass: editText })
                                            dirty = true
                                        }
                                    }
                                }

                                KQuickControls.KeySequenceItem {
                                    Layout.preferredWidth: 140
                                    keySequence: model.shortcut
                                    checkForConflictsAgainst: 2  // ShortcutTypes.GlobalShortcuts
                                    onKeySequenceModified: {
                                        slotModel.set(slotRow.slotIdx, { shortcut: keySequence.toString() })
                                        dirty = true
                                    }
                                }

                                Controls.SpinBox {
                                    Layout.preferredWidth: 75
                                    from: 10; to: 100; stepSize: 5
                                    value: model.widthPercent
                                    textFromValue: function(v) { return v + " %" }
                                    onValueModified: {
                                        slotModel.set(slotRow.slotIdx, { widthPercent: value })
                                        dirty = true
                                    }
                                }

                                Controls.SpinBox {
                                    Layout.preferredWidth: 75
                                    from: 10; to: 100; stepSize: 5
                                    value: model.heightPercent
                                    textFromValue: function(v) { return v + " %" }
                                    onValueModified: {
                                        slotModel.set(slotRow.slotIdx, { heightPercent: value })
                                        dirty = true
                                    }
                                }

                                Controls.ComboBox {
                                    Layout.preferredWidth: 120
                                    model: screenNames
                                    currentIndex: slotModel.get(slotRow.slotIdx)
                                                           ? slotModel.get(slotRow.slotIdx).screenTarget || 0
                                                           : 0
                                    onActivated: function(idx) {
                                        slotModel.set(slotRow.slotIdx, { screenTarget: idx })
                                        dirty = true
                                    }
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

                            // Row 2: secondary fields
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
                                        slotModel.set(slotRow.slotIdx, { opacity: value })
                                        dirty = true
                                    }
                                }

                                Controls.CheckBox {
                                    text: qsTr("All workspaces")
                                    checked: model.allDesktops
                                    onToggled: {
                                        slotModel.set(slotRow.slotIdx, { allDesktops: checked })
                                        dirty = true
                                    }
                                }

                                Controls.CheckBox {
                                    text: qsTr("Auto-hide on focus loss")
                                    checked: model.autoHide
                                    onToggled: {
                                        slotModel.set(slotRow.slotIdx, { autoHide: checked })
                                        dirty = true
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }

                            // Duplicate shortcut warning
                            Kirigami.InlineMessage {
                                width: parent.width
                                type: Kirigami.MessageType.Warning
                                text: qsTr("This shortcut is already assigned to another slot in this list.")
                                visible: {
                                    var sc = model.shortcut
                                    if (!sc) return false
                                    for (var i = 0; i < slotModel.count; i++) {
                                        if (i === slotRow.slotIdx) continue
                                        if (slotModel.get(i).shortcut === sc) return true
                                    }
                                    return false
                                }
                            }

                            Kirigami.Separator { width: parent.width }
                        }
                    }

                    // Empty placeholder
                    Controls.Label {
                        visible: slotModel.count === 0
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
                }
            }

            // ── Hint ─────────────────────────────────────────────────────────
            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                text: qsTr("After saving, the KWin script is reloaded automatically.\nShortcut format: F12 · Meta+F1 · Ctrl+F12")
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
