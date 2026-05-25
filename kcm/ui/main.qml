// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    id: root

    Connections {
        target: kcm
        function onSlotsChanged() { syncSlots() }
        function onActiveWindowsChanged() {
            console.log("[DropdownAny] activeWindows updated: " + kcm.activeWindows.length + " entries")
            windowClassModel.clear()
            for (var i = 0; i < kcm.activeWindows.length; i++) {
                var parts = kcm.activeWindows[i].split(" → ")
                var cls   = parts[0].trim()
                var title = parts.length > 1 ? parts.slice(1).join(" → ") : ""
                console.log("[DropdownAny]   [" + i + "] cls=" + cls + (title ? " title=" + title : ""))
                windowClassModel.append({ cls: cls, title: title })
            }
        }
    }
    Component.onCompleted: syncSlots()

    ListModel { id: slotModel }
    ListModel { id: windowClassModel }

    function syncSlots() {
        slotModel.clear()
        const data = kcm.slots
        for (let i = 0; i < data.length; i++) {
            slotModel.append({
                windowClass:   data[i].windowClass  || "",
                shortcut:      data[i].shortcut     || "",
                widthPercent:  data[i].widthPercent  !== undefined ? data[i].widthPercent  : 100,
                heightPercent: data[i].heightPercent !== undefined ? data[i].heightPercent : 50
            })
        }
    }

    function pushSlot(idx) {
        const row = slotModel.get(idx)
        kcm.setSlot(idx, row.windowClass, row.shortcut, row.widthPercent, row.heightPercent)
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        // ── Active windows ────────────────────────────────────────────────────
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
                    Controls.ToolTip.text: qsTr("Refresh window list")
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.delay: 500
                    onClicked: kcm.fetchActiveWindows()
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
                    model: kcm.activeWindows
                    delegate: Column {
                        width: parent.width

                        Controls.ItemDelegate {
                            width: parent.width

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    text: {
                                        const parts = modelData.split(" → ")
                                        return parts[0] || ""
                                    }
                                    font.family: "monospace"
                                    Layout.preferredWidth: 200
                                    elide: Text.ElideRight
                                }
                                Controls.Label {
                                    text: {
                                        const parts = modelData.split(" → ")
                                        return parts.slice(1).join(" → ")
                                    }
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    color: Kirigami.Theme.disabledTextColor
                                }
                            }

                            hoverEnabled: true
                            Controls.ToolTip.visible: hovered
                            Controls.ToolTip.delay: 500
                            Controls.ToolTip.text: {
                                const cls = modelData.split(" → ")[0] || ""
                                return qsTr("Add \"%1\" as a new dropdown slot").arg(cls)
                            }

                            onClicked: {
                                const cls = modelData.split(" → ")[0] || ""
                                // Fill first empty slot, or create a new one
                                for (let i = 0; i < slotModel.count; i++) {
                                    if (slotModel.get(i).windowClass === "") {
                                        slotModel.set(i, { windowClass: cls })
                                        pushSlot(i)
                                        return
                                    }
                                }
                                kcm.addSlotWithClass(cls)
                            }
                        }
                        Kirigami.Separator { width: parent.width }
                    }
                }

                Controls.Label {
                    visible: kcm.activeWindows.length === 0
                    Layout.fillWidth: true
                    text: qsTr("No windows detected yet…")
                    horizontalAlignment: Text.AlignHCenter
                    color: Kirigami.Theme.disabledTextColor
                    padding: Kirigami.Units.largeSpacing
                }
            }
        }

        // ── Registered slots ──────────────────────────────────────────────────
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

                    Controls.Label { text: "#"; font.bold: true; Layout.preferredWidth: 20 }
                    Controls.Label { text: qsTr("Window class"); font.bold: true; Layout.fillWidth: true }
                    Controls.Label { text: qsTr("Shortcut");     font.bold: true; Layout.preferredWidth: 140 }
                    Controls.Label { text: qsTr("Width %");  font.bold: true; Layout.preferredWidth: 75 }
                    Controls.Label { text: qsTr("Height %"); font.bold: true; Layout.preferredWidth: 75 }
                    Item { Layout.preferredWidth: 30 }
                }
                Kirigami.Separator { Layout.fillWidth: true }

                Repeater {
                    model: slotModel
                    delegate: Column {
                        id: slotRow
                        property int slotIdx: index
                        property string savedClass: ""
                        Component.onCompleted: savedClass = windowClass

                        width: parent.width

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

                                // Set editText imperatively — NOT as a binding.
                                // Qt's internal updateEditText() breaks QML bindings on model
                                // change; we restore from savedClass instead.
                                Component.onCompleted: editText = slotRow.savedClass

                                Connections {
                                    target: windowClassModel
                                    function onCountChanged() {
                                        classCombo.editText = slotRow.savedClass
                                    }
                                }

                                // Show class (monospace) + app title (dimmed) in the dropdown
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

                                // User picks from the dropdown
                                onActivated: function(comboIdx) {
                                    var cls = windowClassModel.get(comboIdx).cls
                                    slotRow.savedClass = cls
                                    editText = cls
                                    slotModel.set(slotRow.slotIdx, { windowClass: cls })
                                    pushSlot(slotRow.slotIdx)
                                }

                                // User types manually → push when focus leaves
                                onActiveFocusChanged: {
                                    if (!activeFocus) {
                                        slotRow.savedClass = editText
                                        slotModel.set(slotRow.slotIdx, { windowClass: editText })
                                        pushSlot(slotRow.slotIdx)
                                    }
                                }
                            }

                            KQuickControls.KeySequenceItem {
                                Layout.preferredWidth: 140
                                keySequence: model.shortcut
                                checkForConflictsAgainst: 2  // GlobalShortcuts
                                onKeySequenceModified: {
                                    slotModel.set(index, { shortcut: keySequence.toString() })
                                    pushSlot(index)
                                }
                            }

                            Controls.SpinBox {
                                Layout.preferredWidth: 75
                                from: 10; to: 100; stepSize: 5
                                value: model.widthPercent
                                textFromValue: function(v) { return v + " %" }
                                onValueModified: {
                                    slotModel.set(index, { widthPercent: value })
                                    pushSlot(index)
                                }
                            }

                            Controls.SpinBox {
                                Layout.preferredWidth: 75
                                from: 10; to: 100; stepSize: 5
                                value: model.heightPercent
                                textFromValue: function(v) { return v + " %" }
                                onValueModified: {
                                    slotModel.set(index, { heightPercent: value })
                                    pushSlot(index)
                                }
                            }

                            Controls.ToolButton {
                                Layout.preferredWidth: 30
                                icon.name: "list-remove"
                                Controls.ToolTip.text: qsTr("Remove this slot")
                                Controls.ToolTip.visible: hovered
                                Controls.ToolTip.delay: 500
                                onClicked: kcm.removeSlot(slotRow.slotIdx)
                            }
                        }

                        Kirigami.InlineMessage {
                            width: parent.width
                            type: Kirigami.MessageType.Warning
                            text: qsTr("This shortcut is already assigned to another slot in this list.")
                            visible: {
                                const sc = model.shortcut
                                if (!sc) return false
                                for (let i = 0; i < slotModel.count; i++) {
                                    if (i === slotRow.slotIdx) continue
                                    if (slotModel.get(i).shortcut === sc) return true
                                }
                                return false
                            }
                        }

                        Kirigami.Separator { width: parent.width }
                    }
                }

                Controls.Label {
                    visible: slotModel.count === 0
                    Layout.fillWidth: true
                    text: qsTr("No slots configured yet — click an active window above or use the Add button below.")
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
                    text: qsTr("Add slot")
                    onClicked: kcm.addSlot()
                }
            }
        }

        // ── Hint ─────────────────────────────────────────────────────────────
        Controls.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            text: qsTr("After saving, reload the script (disable → enable in KWin Scripts) for changes to take effect.\nShortcut format: F12 · Meta+F1 · Ctrl+F12")
        }

        // ── Debug ─────────────────────────────────────────────────────────────
        Kirigami.Card {
            Layout.fillWidth: true

            header: Kirigami.Heading {
                level: 3
                padding: Kirigami.Units.smallSpacing
                text: qsTr("Developer options")
            }

            contentItem: Controls.CheckBox {
                text: qsTr("Enable debug mode — shows an OSD notification on every shortcut trigger with the window class, action taken, and any errors")
                checked: kcm.debugMode
                onToggled: kcm.debugMode = checked
            }
        }
    }
}
