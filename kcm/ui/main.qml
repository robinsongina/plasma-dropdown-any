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
    }
    Component.onCompleted: syncSlots()

    ListModel { id: slotModel }

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

            header: Kirigami.Heading {
                level: 3
                padding: Kirigami.Units.smallSpacing
                text: qsTr("Active windows — click a row to add its class to the first empty slot")
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
                                return qsTr("Add \"%1\" to first empty slot").arg(cls)
                            }

                            onClicked: {
                                const cls = modelData.split(" → ")[0] || ""
                                for (let i = 0; i < slotModel.count; i++) {
                                    if (slotModel.get(i).windowClass === "") {
                                        slotModel.set(i, { windowClass: cls })
                                        pushSlot(i)
                                        return
                                    }
                                }
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
                        width: parent.width

                        RowLayout {
                            width: parent.width
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: index + 1
                                Layout.preferredWidth: 20
                            }

                            Controls.TextField {
                                Layout.fillWidth: true
                                text: model.windowClass
                                placeholderText: index === 0 ? "e.g. konsole" : (index === 1 ? "e.g. kitty" : "")
                                onEditingFinished: {
                                    slotModel.set(index, { windowClass: text })
                                    pushSlot(index)
                                }
                            }

                            KQuickControls.KeySequenceItem {
                                Layout.preferredWidth: 140
                                keySequence: model.shortcut
                                checkForConflictsAgainst: 0
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
                                icon.name: "edit-clear"
                                visible: model.windowClass !== "" || model.shortcut !== ""
                                Controls.ToolTip.text: qsTr("Clear this slot")
                                Controls.ToolTip.visible: hovered
                                Controls.ToolTip.delay: 500
                                onClicked: {
                                    slotModel.set(index, {
                                        windowClass: "", shortcut: "",
                                        widthPercent: 100, heightPercent: 50
                                    })
                                    pushSlot(index)
                                }
                            }
                        }
                        Kirigami.Separator { width: parent.width }
                    }
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
