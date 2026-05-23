#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ID="plasma-dropdown-any"

echo "→ Building KCM config module…"
KCM_DIR="$SCRIPT_DIR/kcm"
cmake -B "$KCM_DIR/build" -S "$KCM_DIR" \
      -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
      -DCMAKE_BUILD_TYPE=Release -Wno-dev -DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON \
      -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF \
      2>&1 | grep -E "Error|error" | grep -v "^--" || true
cmake --build "$KCM_DIR/build" -j"$(nproc)"
cmake --install "$KCM_DIR/build"
# KDEInstallDirs6 may put the .so under lib/plugins/ instead of lib/qt6/plugins/
# Qt 6 searches lib/qt6/plugins/ — ensure both paths have the binary
QT_PLUGIN_DEST="$HOME/.local/lib/qt6/plugins/kwin/effects/configs"
KDE_PLUGIN_SRC="$HOME/.local/lib/plugins/kwin/effects/configs/kcm_dropdown_any.so"
if [[ -f "$KDE_PLUGIN_SRC" ]]; then
    mkdir -p "$QT_PLUGIN_DEST"
    cp "$KDE_PLUGIN_SRC" "$QT_PLUGIN_DEST/kcm_dropdown_any.so"
fi

# Register QT_PLUGIN_PATH for the Plasma session so System Settings finds the KCM
PLASMA_ENV_DIR="$HOME/.config/plasma-workspace/env"
mkdir -p "$PLASMA_ENV_DIR"
cat > "$PLASMA_ENV_DIR/dropdown-any-qt-plugin.sh" << 'ENVEOF'
export QT_PLUGIN_PATH="$HOME/.local/lib/qt6/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
ENVEOF
echo "  KCM built and installed."

echo ""
echo "→ Installing KWin script: $SCRIPT_ID"

# Install or upgrade
if kpackagetool6 --type KWin/Script --install "$SCRIPT_DIR" 2>/dev/null; then
    echo "  Installed."
else
    echo "  Already installed — upgrading."
    kpackagetool6 --type KWin/Script --upgrade "$SCRIPT_DIR"
fi

# Enable
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled" true
echo "  Enabled in kwinrc."

# Reload KWin scripting engine
if qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start 2>/dev/null; then
    echo "  KWin scripting engine reloaded."
else
    echo "  Could not auto-reload — log out and back in (or run: kwin_wayland --replace &)."
fi

echo ""
echo "Done. Open System Settings → Window Management → KWin Scripts"
echo "→ select '$SCRIPT_ID' → Configure to add your window entries."
