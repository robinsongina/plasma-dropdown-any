#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ID="plasma-dropdown-any"
EFFECT_ID="plasma-dropdown-any-slide"
PLASMOID_ID="org.kde.plasma.dropdownany"
PLASMOID_HELPER="$HOME/.local/share/plasma/plasmoids/${PLASMOID_ID}/contents/code/config-helper.sh"

usage() {
    cat >&2 <<'EOF'
Usage: install.sh [component...]

Installs/upgrades the given components only. With no arguments, installs
all three (previous default behavior, unchanged).

Components:
  script      KWin script — the dropdown toggle logic
  plasmoid    Plasma widget — settings UI
  effect      KWin slide effect — animated show/hide

Examples:
  install.sh                  # everything (default)
  install.sh effect           # only the effect
  install.sh script plasmoid  # script + plasmoid, skip the effect
EOF
    exit 1
}

do_script=false
do_plasmoid=false
do_effect=false

if [[ $# -eq 0 ]]; then
    do_script=true
    do_plasmoid=true
    do_effect=true
else
    for arg in "$@"; do
        case "$arg" in
            script)      do_script=true ;;
            plasmoid)    do_plasmoid=true ;;
            effect)      do_effect=true ;;
            -h|--help)   usage ;;
            *)
                echo "ERROR: unknown component '$arg'" >&2
                usage
                ;;
        esac
    done
fi

if $do_script; then
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
fi

if $do_plasmoid; then
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
fi

if $do_effect; then
    echo ""
    echo "→ Installing KWin effect: $EFFECT_ID"

    # Install or upgrade the scoped slide effect. It only animates windows
    # managed by this plugin (see effect/contents/code/main.js), so it's an
    # opt-in alternative to a generic third-party geometry-change effect.
    if kpackagetool6 --type KWin/Effect --install "$SCRIPT_DIR/effect" 2>/dev/null; then
        echo "  Installed."
    else
        echo "  Already installed — upgrading."
        kpackagetool6 --type KWin/Effect --upgrade "$SCRIPT_DIR/effect"
    fi
fi

if $do_script; then
    # Enable KWin script
    kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled" true
    echo "  Enabled in kwinrc."
fi

if $do_effect; then
    # Enable the slide effect
    kwriteconfig6 --file kwinrc --group Plugins --key "${EFFECT_ID}Enabled" true
    echo "  Slide effect enabled in kwinrc."
fi

if $do_script; then
    # Reload KWin scripting engine (window scripts only — the effect still
    # needs a manual disable/re-enable in System Settings → Desktop Effects,
    # or a compositor restart, same as before this flag was added).
    if qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start 2>/dev/null; then
        echo "  KWin scripting engine reloaded."
    else
        echo "  Could not auto-reload — log out and back in (or run: kwin_wayland --replace &)."
    fi
fi

echo ""
echo "Done."

if $do_plasmoid; then
    echo ""
    echo "To configure your dropdown slots, run:"
    echo "  plasmawindowed org.kde.plasma.dropdownany"
    echo ""
    echo "Or use the included shortcut:"
    echo "  bash configure"
fi
