#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ID="plasma-dropdown-any"
EFFECT_ID="plasma-dropdown-any-slide"
PLASMOID_ID="org.kde.plasma.dropdownany"
KWIN_GROUP="Script-plasma-dropdown-any"

# ── Clean up shortcuts from kglobalshortcutsrc ────────────────────────────────
echo "→ Removing shortcuts from kglobalshortcutsrc…"
slot_count=$(kreadconfig6 --file kwinrc --group "$KWIN_GROUP" --key slotCount 2>/dev/null || echo 0)
[[ "$slot_count" =~ ^[0-9]+$ ]] || slot_count=0

for i in $(seq 1 "$slot_count"); do
    cls=$(kreadconfig6 --file kwinrc --group "$KWIN_GROUP" --key "windowClass${i}" 2>/dev/null || true)
    if [[ -n "$cls" ]]; then
        kwriteconfig6 --file kglobalshortcutsrc --group kwin \
            --key "DropdownAny-${cls}" --delete 2>/dev/null || true
        echo "  Removed shortcut: DropdownAny-${cls}"
    fi
done

# Also clean up the resize / utility shortcuts registered by the script
for key in DropdownAny-ListWindows DropdownAny-ResizeHeightInc DropdownAny-ResizeHeightDec \
           DropdownAny-ResizeWidthInc DropdownAny-ResizeWidthDec; do
    kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "$key" --delete 2>/dev/null || true
done

# ── Remove script config group from kwinrc ────────────────────────────────────
echo "→ Removing script config from kwinrc…"
if command -v python3 &>/dev/null; then
    python3 << 'PYEOF'
import configparser, os, sys
path = os.path.expanduser("~/.config/kwinrc")
cfg = configparser.RawConfigParser()
cfg.optionxform = str  # preserve key case
cfg.read(path)
changed = False
for section in ("Script-plasma-dropdown-any", "Effect-plasma-dropdown-any-slide"):
    if cfg.has_section(section):
        cfg.remove_section(section)
        print(f"  Removed [{section}] from kwinrc.")
        changed = True
if changed:
    with open(path, "w") as f:
        cfg.write(f, space_around_delimiters=False)
PYEOF
fi

# ── Remove packages ───────────────────────────────────────────────────────────
echo "→ Removing KWin script package…"
kpackagetool6 --type KWin/Script --remove "$SCRIPT_ID" 2>/dev/null && echo "  Done." || echo "  Not installed."

echo "→ Removing Plasma applet package…"
kpackagetool6 --type Plasma/Applet --remove "$PLASMOID_ID" 2>/dev/null && echo "  Done." || echo "  Not installed."

echo "→ Removing KWin effect package…"
kpackagetool6 --type KWin/Effect --remove "$EFFECT_ID" 2>/dev/null && echo "  Done." || echo "  Not installed."

# ── Disable in kwinrc and reload KWin ────────────────────────────────────────
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled" false
kwriteconfig6 --file kwinrc --group Plugins --key "${EFFECT_ID}Enabled" false
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || \
    qdbus-qt6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || \
    qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

echo ""
echo "Uninstalled $SCRIPT_ID."
