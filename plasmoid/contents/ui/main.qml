// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import org.kde.plasma.plasmoid

/**
 * main.qml — Plasmoid entry point for org.kde.plasma.dropdownany
 *
 * Architecture choice: PlasmoidItem root (required for Plasma/Applet packages)
 * with fullRepresentation set to ConfigEditor.  preferredRepresentation is
 * also set to fullRepresentation so the config UI is shown immediately when
 * the applet is opened (no compact/icon intermediate step).
 *
 * The applet is a configuration-only tool; it has no panel icon or compact
 * view.  Users access it by adding it to the desktop or by invoking it
 * directly via kpackagetool6.
 */
PlasmoidItem {
    id: root

    // Always show the full editor; skip the compact/icon representation.
    preferredRepresentation: fullRepresentation

    fullRepresentation: ConfigEditor {
        anchors.fill: parent
    }
}
