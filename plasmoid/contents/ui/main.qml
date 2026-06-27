// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ── Compact representation — icon shown in panel ──────────────────────────
    compactRepresentation: Item {
        Kirigami.Icon {
            anchors.centerIn: parent
            width:  Math.min(parent.width, parent.height) * 0.8
            height: width
            source: "utilities-terminal"
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    // ── Full representation — popup shown on click ────────────────────────────
    fullRepresentation: Item {
        Layout.minimumWidth:  680
        Layout.preferredWidth: 750
        Layout.minimumHeight: 480
        Layout.preferredHeight: 600

        ConfigEditor {
            anchors.fill: parent
        }
    }
}
