#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ID="plasma-dropdown-any"
PLASMOID_ID="org.kde.plasma.dropdownany"

kpackagetool6 --type KWin/Script --remove "$SCRIPT_ID"
kpackagetool6 --type Plasma/Applet --remove "$PLASMOID_ID"
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled" false

echo "Removed $SCRIPT_ID."
