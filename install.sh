#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ID="plasma-dropdown-any"
PLASMOID_ID="org.kde.plasma.dropdownany"
PLASMOID_HELPER="$HOME/.local/share/plasma/plasmoids/${PLASMOID_ID}/contents/code/config-helper.sh"

echo "→ Installing KWin script: $SCRIPT_ID"

# Install or upgrade KWin script
if kpackagetool6 --type KWin/Script --install "$SCRIPT_DIR" 2>/dev/null; then
    echo "  Installed."
else
    echo "  Already installed — upgrading."
    kpackagetool6 --type KWin/Script --upgrade "$SCRIPT_DIR"
fi

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
echo "Done. Add plasma-dropdown-any to a panel or desktop as a widget"
echo "to configure your dropdown window entries."
