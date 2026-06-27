#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ID="plasma-dropdown-any"
PLASMOID_ID="org.kde.plasma.dropdownany"
PLASMOID_HELPER="$HOME/.local/share/plasma/plasmoids/${PLASMOID_ID}/contents/code/config-helper.sh"

echo "→ Installing KWin script: $SCRIPT_ID"

# Stage only the KWin script files (metadata.json + contents/) in a temp dir.
# Installing the full project root would copy plasmoid/ into the KWin package,
# causing KPackage to find a Plasma/Applet metadata.json inside a KWin/Script
# package and refuse to load the Configure button.
TMP_KWIN=$(mktemp -d)
cp "$SCRIPT_DIR/metadata.json" "$TMP_KWIN/"
cp -r "$SCRIPT_DIR/contents"   "$TMP_KWIN/"

if kpackagetool6 --type KWin/Script --install "$TMP_KWIN" 2>/dev/null; then
    echo "  Installed."
else
    echo "  Already installed — upgrading."
    kpackagetool6 --type KWin/Script --upgrade "$TMP_KWIN"
fi
rm -rf "$TMP_KWIN"

echo ""
echo "→ Installing Plasma applet: $PLASMOID_ID"

# Install or upgrade the Plasmoid package
if kpackagetool6 --type Plasma/Applet --install "$SCRIPT_DIR/plasmoid" 2>/dev/null; then
    echo "  Installed."
else
    echo "  Already installed — upgrading."
    kpackagetool6 --type Plasma/Applet --upgrade "$SCRIPT_DIR/plasmoid"
fi

# Ensure config-helper.sh is executable after install
if [[ -f "$PLASMOID_HELPER" ]]; then
    chmod +x "$PLASMOID_HELPER"
    echo "  config-helper.sh marked executable."
fi

# Enable KWin script
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled" true
echo "  Enabled in kwinrc."

# Reload KWin scripting engine
if qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start 2>/dev/null; then
    echo "  KWin scripting engine reloaded."
else
    echo "  Could not auto-reload — log out and back in (or run: kwin_wayland --replace &)."
fi

echo ""
echo "Done."
echo ""
echo "To configure your dropdown slots, run:"
echo "  plasmawindowed org.kde.plasma.dropdownany"
echo ""
echo "Or use the included shortcut:"
echo "  bash configure"
